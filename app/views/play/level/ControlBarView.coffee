require('app/styles/play/level/control-bar-view.sass')
storage = require 'core/storage'

CocoView = require 'views/core/CocoView'
template = require 'app/templates/play/level/control-bar-view'
{me} = require 'core/auth'
utils = require 'core/utils'

Campaign = require 'models/Campaign'
Classroom = require 'models/Classroom'
Course = require 'models/Course'
CourseInstance = require 'models/CourseInstance'
GameMenuModal = require 'views/play/menu/GameMenuModal'
LevelSetupManager = require 'lib/LevelSetupManager'
CreateAccountModal = require 'views/core/CreateAccountModal'

module.exports = class ControlBarView extends CocoView
  id: 'control-bar-view'
  template: template

  subscriptions:
    'level:disable-controls': 'onDisableControls'
    'level:enable-controls': 'onEnableControls'
    'ipad:memory-warning': 'onIPadMemoryWarning'

  events:
    'click #next-game-button': -> Backbone.Mediator.publish 'level:next-game-pressed', {}
    'click #game-menu-button': 'showGameMenuModal'
    'click': -> Backbone.Mediator.publish 'tome:focus-editor', {}
    'click .levels-link-area': 'onClickHome'
    'click .home a': 'onClickHome'
    'click #control-bar-sign-up-button': 'onClickSignupButton'
    'click [data-toggle="coco-modal"][data-target="core/CreateAccountModal"]': 'openCreateAccountModal'

  constructor: (options) ->
    @supermodel = options.supermodel
    @courseID = options.courseID
    @courseInstanceID = options.courseInstanceID

    @worldName = options.worldName
    @session = options.session
    @level = options.level
    @levelSlug = @level.get('slug')
    @levelID = @levelSlug or @level.id
    @spectateGame = options.spectateGame ? false
    @observing = options.session.get('creator') isnt me.id

    @levelNumber = ''
    if @level.isType('course', 'game-dev', 'web-dev') and @level.get('campaignIndex')?
      @levelNumber = @level.get('campaignIndex') + 1
    if @courseInstanceID
      @courseInstance = new CourseInstance(_id: @courseInstanceID)
      jqxhr = @courseInstance.fetch()
      @supermodel.trackRequest(jqxhr)
      new Promise(jqxhr.then).then(=>
        @classroom = new Classroom(_id: @courseInstance.get('classroomID'))
        @course = new Course(_id: @courseInstance.get('courseID'))
        @supermodel.trackRequest @classroom.fetch()
        @supermodel.trackRequest @course.fetch()
      )
    else if @courseID
      @course = new Course(_id: @courseID)
      jqxhr = @course.fetch()
      @supermodel.trackRequest(jqxhr)
      new Promise(jqxhr.then).then(=>
        @campaign = new Campaign(_id: @course.get('campaignID'))
        @supermodel.trackRequest(@campaign.fetch())
      )
    super options
    if @level.get 'replayable'
      @listenTo @session, 'change-difficulty', @onSessionDifficultyChanged

  setLevelName: (overideLevelName) ->
    @levelName = overideLevelName
    @render()

  onLoaded: ->
    if @classroom
      @levelNumber = @classroom.getLevelNumber(@level.get('original'), @levelNumber)
      newClassroomItemsSetting = @classroom.get('classroomItems', true)
      oldClassroomItemsSetting = me.lastClassroomItems()
      me.setLastClassroomItems @classroom.get('classroomItems', true)
      if newClassroomItemsSetting isnt oldClassroomItemsSetting and @level.isType('course')
        # Teacher must have just changed the setting, so we need to reload the page
        me.setLastClassroomItems newClassroomItemsSetting
        noty text: 'Classroom items & gems setting changed; reloading', layout: 'topCenter', type: 'success', killer: false, timeout: 2000
        _.delay (-> document.location.reload()), 2000
    else if @campaign
      @levelNumber = @campaign.getLevelNumber(@level.get('original'), @levelNumber)
    if application.getHocCampaign() or @level.get('assessment')
      @levelNumber = null
    super()

  openCreateAccountModal: (e) ->
    e.stopPropagation()
    @openModalView new CreateAccountModal()

  setBus: (@bus) ->

  getRenderData: (c={}) ->
    super c
    c.worldName = @worldName
    c.ladderGame = @level.isLadder()
    if @level.get 'replayable'
      c.levelDifficulty = @session.get('state')?.difficulty ? 0
      if @observing
        c.levelDifficulty = Math.max 0, c.levelDifficulty - 1  # Show the difficulty they won, not the next one.
      c.difficultyTitle = "#{$.i18n.t 'play.level_difficulty'}#{c.levelDifficulty}"
      @lastDifficulty = c.levelDifficulty
    c.spectateGame = @spectateGame
    c.observing = @observing
    @homeViewArgs = [{supermodel: if @hasReceivedMemoryWarning then null else @supermodel}]
    gameDevCampaign = application.getHocCampaign()
    if gameDevCampaign and not @level.isLadder()
      @homeLink = "/play/#{gameDevCampaign}"
      @homeViewClass = 'views/play/CampaignView'
      @homeViewArgs.push gameDevCampaign
    else if me.isSessionless()
      @homeLink = "/teachers/courses"
      @homeViewClass = "views/courses/TeacherCoursesView"
    else if @level.isLadder()
      levelID = @level.get('slug')?.replace(/\-tutorial$/, '') or @level.id
      @homeLink = "/play/ladder/#{levelID}"
      @homeViewClass = 'views/ladder/LadderView'
      @homeViewArgs.push levelID
      if leagueID = utils.getQueryVariable('league') or utils.getQueryVariable('course-instance')
        leagueType = if @level.isType('course-ladder') or (@level.isType('ladder') and utils.getQueryVariable('course-instance')) then 'course' else 'clan'
        @homeViewArgs.push leagueType
        @homeViewArgs.push leagueID
        @homeLink += "/#{leagueType}/#{leagueID}"
        if tournamentId = utils.getQueryVariable('tournament')
          @homeLink += "?tournament=#{tournamentId}"
    else if @level.isType('course') or @courseID
      @homeLink = "/play"
      if @course?
        @homeLink += "/#{@course.get('campaignID')}"
        @homeViewArgs.push @course.get('campaignID')
      if @courseInstanceID
        @homeLink += "?course-instance=#{@courseInstanceID}"

      @homeViewClass = 'views/play/CampaignView'
    else if @level.isType('hero', 'hero-coop', 'game-dev', 'web-dev') or window.serverConfig.picoCTF
      @homeLink = '/play'
      @homeViewClass = 'views/play/CampaignView'
      campaign = @level.get 'campaign'
      @homeLink += '/' + campaign
      @homeViewArgs.push campaign
    else
      @homeLink = '/'
      @homeViewClass = 'views/HomeView'
    c.editorLink = "/editor/level/#{@level.get('slug') or @level.id}"
    c.homeLink = @homeLink
    c

  showGameMenuModal: (e, tab=null) ->
    gameMenuModal = new GameMenuModal level: @level, session: @session, supermodel: @supermodel, showTab: tab, classroomAceConfig: @options.classroomAceConfig
    @openModalView gameMenuModal
    @listenToOnce gameMenuModal, 'change-hero', ->
      @setupManager?.destroy()
      @setupManager = new LevelSetupManager({supermodel: @supermodel, level: @level, levelID: @levelID, parent: @, session: @session, courseID: @courseID, courseInstanceID: @courseInstanceID})
      @setupManager.open()

  onClickHome: (e) ->
    if @level.isType('course')
      category = if me.isTeacher() then 'Teachers' else 'Students'
      window.tracker?.trackEvent 'Play Level Back To Levels', category: category, levelSlug: @levelSlug
    e.preventDefault()
    e.stopImmediatePropagation()
    Backbone.Mediator.publish 'router:navigate', route: @homeLink, viewClass: @homeViewClass, viewArgs: @homeViewArgs

  onClickSignupButton: (e) ->
    window.tracker?.trackEvent 'Started Signup', category: 'Play Level', label: 'Control Bar', level: @levelID

  onDisableControls: (e) -> @toggleControls e, false
  onEnableControls: (e) -> @toggleControls e, true
  toggleControls: (e, enabled) ->
    return if e.controls and not ('level' in e.controls)
    return if enabled is @controlsEnabled
    @controlsEnabled = enabled
    @$el.toggleClass 'controls-disabled', not enabled

  onIPadMemoryWarning: (e) ->
    @hasReceivedMemoryWarning = true

  onSessionDifficultyChanged: ->
    return if @session.get('state')?.difficulty is @lastDifficulty
    @render()

  destroy: ->
    @setupManager?.destroy()
    super()
