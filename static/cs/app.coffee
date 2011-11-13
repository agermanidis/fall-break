class Handler
  constructor: ->
    @subscribers = []

  subscribe: (s) ->
    @subscribers.push s

  unsubscribe: (s) ->
    @subscribers.remove s

  emit: (msg) ->
    for s in @subscribers
      s msg

class User extends Handler
  lowers: [97, 119, 115, 101, 100, 102, 116, 103, 121, 104, 117, 106, 107, 111, 108, 112, 186]
  uppers: [65, 87, 83, 69, 68, 70, 84, 71, 89, 72, 85, 74, 75, 79, 76, 80, 59]

  constructor: ->
    super()
    $("*")
      .keydown (e) =>
        if (key = @getKey(e)) isnt -1
          @emit
            key: key
            state: on

      .keyup (e) =>
        if (key = @getKey(e)) isnt -1
          @emit
            key: key
            state: off

  getKey: (e) ->
    if (k = e.which) is 16
      'sustain'
    else if k in @lowers
      @lowers.indexOf(k)
    else if k in @uppers
      @uppers.indexOf(k)
    else -1


class RecordPlayer extends Handler
  constructor: (@data) ->
    super()
    @timer = new CountdownTimer _.first(_.last(@data))
    for t, e of data
      @timer.at t, ->
        @emit e

  play: ->
    @timer.start()

  pause: ->
    @timer.stop()

class Timer
  constructor: ->
    @t = 0
    @cbs = {}

  start: ->
    @intervalID = setInterval @update, 100

  stop:
    clearInterval @intervalID

  update: ->
    @t += 100
    if @cbs[@t]?
      cb() for cb in @cbs[@t]

  get: ->
    @t

  reset: ->
    @t = 0

  at: (t, cb) ->
    if @cbs[t]? then @cbs[t].push(cb) else @cbs[t] = [cb]

class CountdownTimer
  constructor: (t) ->
    super()
    @endcbs = []
    @at t, =>
      @stop
      cb() for cb in @endcbs

  subscribe: (cb) ->
    @endcbs.push cb

class Recorder
  constructor: (@handler) ->
    @timer = new Timer
    @data = []
    @start()

  start: ->
    @handler.subscribe @captureEvent
    @timer.start()

  stop: ->
    @handler.unsubscribe @captureEvent
    @timer.stop()

  get: ->
    @data

  captureEvent: (evt) ->
    t = @timer.get()
    @data.push [t, evt]

  save: (cb) ->
    $.ajax
      type: 'POST'
      url: "/save"
      dataType: 'json'
      data: @data
      success: (id) ->
        cb id

class Clip
  constructor: (@el) ->
    @clip_id = parseInt(@el.attr("id").split('video')[1].split('_')[0]) - 1
    @state = off
    @sustained = off
    @oncbs = []
    @offcbs = []
    @onsustainedoncbs = []
    @onsustainedoffcbs = []
    @fadingOut = off
    @el.css("z-index", "0")
       .hide()
       .get(0).load()

  reload: ->
    @el.load()

  show: (zindex) ->
    if @fadingOut and @sustained
      @el.stop()
         .fadeIn(10000)
         .show()
         .get(0).play()
    else
      @el.css("z-index", zindex or 10000)
         .css("opacity", "1")
         .stop()
         .show()
         .get(0).play()

  disappear: =>
    @fadingOut = off
    @el.get(0).pause()
    @el.hide()
       .removeAttr("class")

  activate: ->
    unless @state
      @state = on
      for cb in @oncbs
        cb()

  deactivate: ->
    if @state
      @state = off
      if @sustained
        @fadingOut = on
        @el.fadeOut 10000, @disappear
      else
        @disappear()
      for cb in @offcbs
        cb()

  sustainOn: ->
    @sustained = on

  sustainOff: ->
    @sustained = off
    unless @state
      @disappear()

  onActivated: (cb) ->
    @oncbs.push cb

  onDeactivated: (cb) ->
    @offcbs.push cb

  onLoaded: (cb) ->
    @el.bind('loadeddata', cb)

  position: (p, g) ->
    old_class = @el.attr("class")
    new_class = "p#{p+1}g#{g}"
    unless old_class == new_class
        @el.removeClass(old_class).addClass(new_class)

class SplashScreen
  constructor: (@el) ->
    @count = 0
    @progressBar = @el.find "#progress_bar"
    @progress = @progressBar.find "#progress"
    @progressText = @el.find "#progress_text"

  videoLoaded: =>
    @count += 1
    if @count > 18
      @count = 18
    @progress.animate {width: "+#{@count * @progressBar.width() / 18}"}, 100
    @progressText.html("#{@count}/18")

  hide: =>
    @el.hide()

class Environment
  constructor: ->
    @viewer = new Viewer $("#viewer")
    @soundEngine = new SoundEngine $("#sound_engine")
    @splashScreen = new SplashScreen $("#splash_screen")
    @tutorial = new Tutorial $("#tutorial")
    @clips = []
    @videoLoadedCallbacks = []

    $("#keysLink").click =>
      $("#keys").toggle()
    $("#keys").click =>
      $("#keys").toggle()
    $("#closeButton").click =>
      $("#keys").hide()

    activated = (i) => () =>
        if @hasStarted()
          @viewer.activated(@clips[i])
          @tutorial.activated(i)
        else
          @splashScreen.keyActivated(i)
        @soundEngine.activated(@clips[i])

    deactivated = (i) => () =>
        if @hasStarted()
          @viewer.deactivated(@clips[i])
          @tutorial.deactivated(i)
        else
          @splashScreen.keyDeactivated(i)
        @soundEngine.deactivated(@clips[i])

    for i in [1..17]
      c = new Clip $("#video#{i}")
      @clips.push c
      c.onActivated activated(i - 1)
      c.onDeactivated deactivated(i - 1)
      c.onLoaded @clipLoaded

    @user = new User
    @setHandler @user
    @callbacks = []
    @viewer.hide()
    @tutorial.hide()
    @started = off

    @start = _.after @clips.length, =>
      todo = =>
        @splashScreen.hide()
        @viewer.show()
        @tutorial.show()
        $("#footer").hide()
        $("#keysLink").show()
        @started = on
      setTimeout todo, 10000

    @soundEngine.onLoadedAudio @clipLoaded
    @subscribeLoading(cb) for cb in [@start, @splashScreen.videoLoaded]

  hasStarted: ->
    @started

  subscribeLoading: (cb) =>
    @videoLoadedCallbacks.push cb

  clipLoaded: =>
    for cb in @videoLoadedCallbacks
      cb()

  setHandler: (h) ->
    @handler.unsubscribe @emitEvent if @handler?
    h.subscribe @emitEvent
    @handler = h

  emitEvent: (evt) =>
    {state, key} = evt

    if key is 'sustain'
      if state
        $("#sustain_indicator").show()
        clip.sustainOn() for clip in @clips
        @viewer.sustained()
        @tutorial.sustained()
      else
        $("#sustain_indicator").hide()
        clip.sustainOff() for clip in @clips
        @viewer.unsustained()
        @tutorial.unsustained()
    else
      if state
        @clips[key].activate()
      else
        @clips[key].deactivate()

  onEvent: (cb) ->
    @callbacks.push(cb)

class Set
  constructor: (elements) ->
    @elements = elements or []

  add: (element) ->
    @elements = _.union @elements, [element]
    @elements.sort()

  remove: (element) ->
    @elements = _.without @elements, element

  contains: (element) ->
    element in @elements

  size: ->
    @elements.length

  equal: (other) ->
    for element in @elements
      unless other.contains(element)
        return false

    @size() == other.size()

class Tutorial
  steps: [
    new Set([0]),
    new Set([4]),
    new Set([7]),
    new Set([0, 4, 7]),
    new Set([0, 'SUSTAIN']),
    new Set([4, 'SUSTAIN']),
    new Set([7, 'SUSTAIN'])
  ]

  constructor: (@el) ->
    @active = new Set
    @step = 0
    @alive = on
    @clips = for i in [1..4]
      c = new Clip $("#tutorial_video#{i}")
      c.el.get(0).play()
      c.el.get(0).pause()
      c
    @renderStep @step
    $("#skipTutorialButton").click =>
      @kill()

  show: => @el.show()
  hide: => @el.hide()

  correspondences:
    0: 0
    4: 1
    7: 2
    'SUSTAIN': 3

  renderStep: (step) ->
    $("#skipTutorialButton").show()
    elements = @steps[step].elements
    len = elements.length
    for el,i in elements
      c = @clips[@correspondences[el]]
      c.show()
      c.position(i, len)
      c.el.get(0).volume = 0

  clearScreen: ->
    for c in @clips
      c.deactivate()
      c.el.hide()
      c.reload()
    $("#skipTutorialButton").hide()

  kill: ->
    @alive = off
    @el.hide()

  activated: (note) ->
    if @alive
      @active.add note
      @update()

  deactivated: (note) ->
    if @alive
      @active.remove note
      @update()

  sustained: ->
    if @alive
      @active.add 'SUSTAIN'

  unsustained: ->
    if @alive
      @active.remove 'SUSTAIN'

  update: ->
    unless @active.equal(@steps[@step])
      return

    @clearScreen()
    @step += 1

    if @step == @steps.length
      @kill()
    else
      if 1 <= @step <= 4
        setTimeout (=>@renderStep @step), 3000
      else
        @renderStep @step

class Viewer
  constructor: (@el) ->
    @active = []
    @timeouts = []
    @sustain = off
    @count = 10000

  show: =>
    @el.show()
       .focus()

  hide: => @el.hide()

  clearTimeouts: ->
    clearTimeout timeout for timeout in @timeouts

  activated: (note) ->
    @clearTimeouts()
    prev = @active.length
    @active = _.union @active, [note]
    now = @active.length
    @update()

  deactivated: (note) ->
    @clearTimeouts()
    @active = _.without @active, note
    if @active.length < 2
      @update()
    else
      @timeouts.push(setTimeout (=> @update()), 800)

  sustained: ->
    @sustain = on
    @update()

  unsustained: ->
    @sustain = off
    @count = 10000

  update: ->
    len = @active.length
    for v,i in @active
      v.show(@count)
      @count -= 1
      v.position i, len

class SoundEngine
  notes: ['C_low', 'C_sharp_low', 'D_low', 'D_sharp_low', 'E_low',
          'F', 'F_sharp', 'G', 'G_sharp', 'A', 'A_sharp', 'B', 'C_high',
          'C_sharp_high', 'D_high', 'D_sharp_high', 'E_high']

  enable: ->
    @enabled = on

  disable: ->
    @enabled = off

  constructor: (@el) ->
    @fmt = if window.chrome? then "mp3" else "ogg"
    @count = 0
    @enabled = on
    @loadedCount = 0
    @loadedcbs = []
    @loadedAudios = _.after @notes.length, =>
      for cb in @loadedcbs
        cb()
    for note in @notes
      e = $("##{note}_prototype_#{@fmt}")
        .bind('canplaythrough', @loadedAudios)

  activated: (c) ->
    if @enabled
      @play @notes[c.clip_id]

  deactivated: (c) ->

  play: (note) ->
    audio = new Audio("notes/#{note}.#{@fmt}")
    @el.append(audio)
    cleanup = =>
      $(audio).remove()
    setTimeout cleanup, 5000
    audio.play()

  onLoadedAudio: (cb) ->
    @loadedcbs.push cb

$ ->
  env = new Environment
