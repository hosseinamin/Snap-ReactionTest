$mkOption = (value, html, selected) -> $('<option>').attr('value', value).prop('selected', !!selected).html(html)
$selectReset = ($sel, list) ->
  $sel.children().remove()
  _.each(list, (item) ->
    $sel.append($mkOption(item.value, item.label, item['default']))
  )
  $sel


parseLocationQuery = () ->
  output = {}
  query = window.location.search.substring(1)
  for entry in query.split('&')
    pair = entry.split('=')
    output[decodeURIComponent(pair[0])] = pair[1]
  output
 
window.Parsley
  .addValidator('fileType', {
    requirementType: 'string'
    validateString: (_value, typePttrn, parsleyInstance) ->
      files = parsleyInstance.$element[0].files;
      typeRegex = new RegExp(typePttrn)
      files.length != 1  or typeRegex.test(files[0].type);
    messages: {
      en: 'Selected file is not image',
    }
  });
  
class GameSetup
  constructor: (formel) ->
    self = @
    if not GameConfig then throw new Error("GameConfig is not defined!")
    @$form = $(formel)
    @$form.submit(($evt)->
      $evt.preventDefault()
      if not self.$form.parsley().isValid()
        return # validation is not ready
      if parseInt($('[name=total_time]').val()) == -1 and \
         parseInt($('[name=slides_count]').val()) == -1
        return alert("Total Time and Number of slides cannot be unknown")
      # not defined yet
      self._formData()
      .then (data) ->
        self.$form.find('.error-msg').html("").hide()
        $(self).trigger('submit', data)
      .catch (err) ->
        self.$form.find('.error-msg').html(err).show()
    )
    @$imagesdiv = @$form.find('[data-images-form]')
    if @$imagesdiv.length != 1
      throw new Error("GameSetup form needs one and only one data-images-form")
    @storedimages = []
    @imagesPresetByValue = _.object(
      _.pluck(GameConfig.imagesPresetList, 'value')
              GameConfig.imagesPresetList
    )
    imgtypepttrn = /^image\//
    @$form.find('[name=images_preset]').bind('change', ->
      $inp = $(@)
      preset = self.imagesPresetByValue[$inp.val()]
      haspreset = preset? and preset.images?
      if haspreset
        self.storedimages = _.map(preset.images, (url) -> { image_url: url })
      else
        self.storedimages = []
      self.$imagesdiv.children().remove() # remove imagesdiv anyway
      self.$imagesdiv[if haspreset then 'hide' else 'show']()
      self.$form.find('.select-images')[if haspreset then 'hide' else 'show']()
    )
    @$form.find('[name=images_select]').bind('change', ->
      $imagesinp = $(@)
      files = _.map(@files, (file) -> file) # to array
      # clear files
      $newinp = $imagesinp.clone()
      $newinp.bind('change', arguments.callee)
      $imagesinp.replaceWith($newinp)
      storeAnImage = ->
        file = files.shift()
        if not file
          # complete
          return
        if imgtypepttrn.test(file.type)
          self.addImage(file)
            .then -> storeAnImage()
            .catch -> storeAnImage()
        else
          storeAnImage()
      storeAnImage()
    )
    @$form.find('.clear-images').bind('click', ->
      self.storedimages = []
      self.$imagesdiv.children().remove()
    )
    @$imagesdiv.on('click', '.remove-image', ($evt) ->
      $evt.preventDefault()
      $imagectr = $($evt.target).parents('.game-image-ctr')
      if $imagectr and self.$imagesdiv[0] == $imagectr.parent()[0]
        imagectr = $imagectr[0]
        index = _.findIndex(self.$imagesdiv.children(), (c) -> c == imagectr)
        if index != -1
          self.storedimages.splice(index, 1)
          $imagectr.remove()
    )
  
  load: ->
    self = @
    promises = []
    # load image template
    if not GameConfig.imageFormTemplate
      if not GameConfig._promise_imageFormTemplate?
        GameConfig._promise_imageFormTemplate = \
          $.ajax(GameConfig.imageFormTemplateUrl).then (tpl) ->
            delete GameConfig._promise_imageFormTemplate
            if typeof tpl != 'string'
              throw new Error("String response expected got #{typeof tpl}")
            GameConfig.imageFormTemplate = _.template(tpl) # define template
      promises.push GameConfig._promise_imageFormTemplate
    else if typeof GameConfig.imageFormTemplate == 'string'
      GameConfig.imageFormTemplate = _.template(GameConfig.imageFormTemplate)
    # promise on ready
    $.when.apply($, promises).then ->
      self._initiate()

  _initiate: ->
    @resetSelectOptions()
    # initialize from queries
    locquery = parseLocationQuery()
    if locquery.preset
      @$form.find('[name=images_preset]').val(locquery.preset)
    @$form.parsley(GameConfig.ParsleyConfig)

  resetSelectOptions: ->
    $selectReset(@$form.find('[name=slide_image_count]').first(),
                 GameConfig.slideFormatList)
    $selectReset(@$form.find('[name=images_preset]').first(),
                 GameConfig.imagesPresetList)
      .trigger('change') # perform images_preset check
    $selectReset(@$form.find('[name=have_match_proportion]').first(),
                 GameConfig.haveMatchProportionList)
    $selectReset(@$form.find('[name=slide_timeout]').first(),
                 GameConfig.slideTimeoutList)
    $selectReset(@$form.find('[name=total_time]').first(),
                 GameConfig.totalTimeList)
    $selectReset(@$form.find('[name=next_slide_pause]').first(),
                 GameConfig.nextSlidePause)
    $selectReset(@$form.find('[name=slides_count]').first(),
                 GameConfig.slidesCountList)

  _file2url: (file) ->
    deferred = $.Deferred()
    if URL && URL.createObjectURL
      deferred.resolve(URL.createObjectURL(file))
      return deferred.promise()
    reader = new FileReader()
    reader.addEventListener('load', ->
      deferred.resolve(reader.result)
    , false)
    reader.readAsDataURL(file)
    deferred.promise()

  _loadImage: (url) ->
    deferred = $.Deferred()
    img = new Image()
    img.src = url
    img.onload = ->
      deferred.resolve()
    img.onerror = ->
      deferred.reject("Could not load image: " + url)
    deferred.promise()

  addImage: (file) ->
    self = @
    @_file2url(file).then (image_url) ->
      self._loadImage(image_url).then ->
        imagedata =
          image_url: image_url
          file: file
        self.storedimages.push(imagedata)
        self.$imagesdiv.append(GameConfig.imageFormTemplate({
          image_url: image_url
        }))

  _formData: ->
    promises = []
    ret = {}
    self = @
    inputParseInt = (inp) -> parseInt(inp.value)
    inputParseFloat = (inp) -> parseFloat(inp.value)
    inputParseCheckbox = (inp) -> inp.checked
    erridx = _.findIndex([
      {n: 'total_time', c:inputParseInt},
      {n: 'slide_image_count', c:inputParseInt}
      {n: 'slide_timeout', c:inputParseInt}
      {n: 'have_match_proportion', c:inputParseFloat}
      {n: 'withaudio', c:inputParseCheckbox }
      {n: 'next_slide_pause', c: inputParseInt }
      {n: 'slides_count', c: inputParseInt }
    ], (item) ->
      $inp = self.$form.find("[name=#{item.n}]").first()
      val = $inp.val()
      if $inp.length == 0 or not $inp.parsley().isValid()
        return true
      if typeof item.c == 'function'
        val = item.c($inp[0])
      ret[item.n] = val
      return false
    )
    if erridx != -1
      deferred = $.Deferred()
      deferred.reject("Form input is not valid")
      return deferred.promise()
    if @storedimages.length < GameConfig.leastImageLength
      deferred = $.Deferred()
      deferred.reject("Need for at #{GameConfig.leastImageLength} least images to build the game")
      return deferred.promise()
    ret.images = @storedimages
    preset = self.imagesPresetByValue[@$form.find('[name=images_preset]').val()]
    haspreset = preset? and preset.images?
    # update stored images if needed
    if not haspreset
      $images_ctr = @$imagesdiv.children()
      _.each(@storedimages, (imagedata, index) ->
        if index < $images_ctr.length
          inp = $($images_ctr[index]).find('input[type=file]')[0]
          if inp and inp.files.length == 1 and inp.files[0] != imagedata.file
            # update image data
            newfile = inp.files[0]
            promises.push(
              @_file2url(file).then (image_url) ->
                self._loadImage(image_url).then ->
                  imagedata.image_url = image_url
                  imagedata.file = newfile
            )

      )
    $.when.apply($, promises).then(-> ret)
    
    
window.GameSetup = GameSetup
