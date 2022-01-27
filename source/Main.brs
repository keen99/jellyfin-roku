sub Main (args as dynamic) as void

    ' If the Rooibos files are included in deployment, run tests
    'bs:disable-next-line
    if type(Rooibos__Init) = "Function" then Rooibos__Init()

   ' The main function that runs when the application is launched.
    m.screen = CreateObject("roSGScreen")

    ' Set global constants
    setConstants()

    m.port = CreateObject("roMessagePort")
    m.screen.setMessagePort(m.port)
    m.scene = m.screen.CreateScene("JFScene")
    m.screen.show()

    ' Set any initial Global Variables
    m.global = m.screen.getGlobalNode()

    playstateTask = CreateObject("roSGNode", "PlaystateTask")
    playstateTask.id = "playstateTask"

    sceneManager = CreateObject("roSGNode", "SceneManager")

    m.global.addFields({ app_loaded: false, playstateTask: playstateTask, sceneManager: sceneManager })

    app_start:
    ' First thing to do is validate the ability to use the API
    if not LoginFlow() then return
    sceneManager.callFunc("clearScenes")

    ' load home page
    sceneManager.currentUser = m.user.Name
    group = CreateHomeGroup()
    group.userConfig = m.user.configuration
    group.callFunc("loadLibraries")
    sceneManager.callFunc("pushScene", group)

    m.scene.observeField("exit", m.port)

    ' Handle input messages
    input = CreateObject("roInput")
    input.SetMessagePort(m.port)

    m.device = CreateObject("roDeviceInfo")
    m.device.setMessagePort(m.port)
    m.device.EnableScreensaverExitedEvent(true)
    m.device.EnableAppFocusEvent(false)

    ' Check if we were sent content to play with the startup command (Deep Link)
    if (args.mediaType <> invalid) and (args.contentId <> invalid)
        video = CreateVideoPlayerGroup(args.contentId)

        if video <> invalid
            sceneManager.callFunc("pushScene", video)
        else
            dialog = createObject("roSGNode", "Dialog")
            dialog.id = "OKDialog"
            dialog.title = tr("Not found")
            dialog.message = tr("The requested content does not exist on the server")
            dialog.buttons = [tr("OK")]
            m.scene.dialog = dialog
            m.scene.dialog.observeField("buttonSelected", m.port)
        end if
    end if

    ' This is the core logic loop. Mostly for transitioning between scenes
    ' This now only references m. fields so could be placed anywhere, in theory
    ' "group" is always "whats on the screen"
    ' m.scene's children is the "previous view" stack
    while true
        msg = wait(0, m.port)
        if type(msg) = "roSGScreenEvent" and msg.isScreenClosed()
            dlog("CLOSING SCREEN", "Main")
            return
        else if isNodeEvent(msg, "exit")
            return
        else if isNodeEvent(msg, "closeSidePanel")
            group = sceneManager.callFunc("getActiveScene")
            if group.lastFocus <> invalid
                group.lastFocus.setFocus(true)
            else
                group.setFocus(true)
            end if
        else if isNodeEvent(msg, "quickPlayNode")
            reportingNode = msg.getRoSGNode()
            itemNode = reportingNode.quickPlayNode
            if itemNode = invalid or itemNode.id = "" then return
            if itemNode.type = "Episode" or itemNode.type = "Movie" or itemNode.type = "Video"
                video = CreateVideoPlayerGroup(itemNode.id)
                if video <> invalid
                    sceneManager.callFunc("pushScene", video)
                end if
            end if
        else if isNodeEvent(msg, "selectedItem")
            ' If you select a library from ANYWHERE, follow this flow
            selectedItem = msg.getData()
            if selectedItem.type = "CollectionFolder" or selectedItem.type = "UserView" or selectedItem.type = "Folder" or selectedItem.type = "Channel" or selectedItem.type = "Boxset"
                group = CreateItemGrid(selectedItem)
                sceneManager.callFunc("pushScene", group)
            else if selectedItem.type = "Episode"
                ' play episode
                ' todo: create an episode page to link here
                video_id = selectedItem.id
                video = CreateVideoPlayerGroup(video_id)
                if video <> invalid
                    sceneManager.callFunc("pushScene", video)
                end if
            else if selectedItem.type = "Series"
                group = CreateSeriesDetailsGroup(selectedItem.json)
            else if selectedItem.type = "Movie"
                ' open movie detail page
                group = CreateMovieDetailsGroup(selectedItem)
            else if selectedItem.type = "TvChannel" or selectedItem.type = "Video" or selectedItem.type = "Program"
                ' play channel feed
                video_id = selectedItem.id

                ' Show Channel Loading spinner
                dialog = createObject("roSGNode", "ProgressDialog")
                dialog.title = tr("Loading Channel Data")
                m.scene.dialog = dialog

                video = CreateVideoPlayerGroup(video_id)
                dialog.close = true

                if video <> invalid
                    sceneManager.callFunc("pushScene", video)
                else
                    dialog = createObject("roSGNode", "Dialog")
                    dialog.id = "OKDialog"
                    dialog.title = tr("Error loading Channel Data")
                    dialog.message = tr("Unable to load Channel Data from the server")
                    dialog.buttons = [tr("OK")]
                    m.scene.dialog = dialog
                    m.scene.dialog.observeField("buttonSelected", m.port)
                end if
            else
                ' TODO - switch on more node types
                message_dialog("This type is not yet supported: " + selectedItem.type + ".")
            end if
        else if isNodeEvent(msg, "movieSelected")
            ' If you select a movie from ANYWHERE, follow this flow
            node = getMsgPicker(msg, "picker")
            group = CreateMovieDetailsGroup(node)
        else if isNodeEvent(msg, "seriesSelected")
            ' If you select a TV Series from ANYWHERE, follow this flow
            node = getMsgPicker(msg, "picker")
            group = CreateSeriesDetailsGroup(node)
        else if isNodeEvent(msg, "seasonSelected")
            ' If you select a TV Season from ANYWHERE, follow this flow
            ptr = msg.getData()
            ' ptr is for [row, col] of selected item... but we only have 1 row
            series = msg.getRoSGNode()
            node = series.seasonData.items[ptr[1]]
            group = CreateSeasonDetailsGroup(series.itemContent, node)
        else if isNodeEvent(msg, "episodeSelected")
            ' If you select a TV Episode from ANYWHERE, follow this flow
            node = getMsgPicker(msg, "picker")
            video_id = node.id
            video = CreateVideoPlayerGroup(video_id)
            if video <> invalid
                sceneManager.callFunc("pushScene", video)
            end if
        else if isNodeEvent(msg, "search_value")
            query = msg.getRoSGNode().search_value
            group.findNode("SearchBox").visible = false
            options = group.findNode("SearchSelect")
            options.visible = true
            options.setFocus(true)

            dialog = createObject("roSGNode", "ProgressDialog")
            dialog.title = tr("Loading Search Data")
            m.scene.dialog = dialog
            results = SearchMedia(query)
            dialog.close = true
            options.itemData = results
            options.query = query
        else if isNodeEvent(msg, "itemSelected")
            ' Search item selected
            node = getMsgPicker(msg)
            ' TODO - swap this based on target.mediatype
            ' types: [ Series (Show), Episode, Movie, Audio, Person, Studio, MusicArtist ]
            if node.type = "Series"
                group = CreateSeriesDetailsGroup(node)
            else
                group = CreateMovieDetailsGroup(node)
            end if
        else if isNodeEvent(msg, "buttonSelected")
            ' If a button is selected, we have some determining to do
            btn = getButton(msg)
            group = sceneManager.callFunc("getActiveScene")
            if btn <> invalid and btn.id = "play-button"
                ' Check is a specific Audio Stream was selected
                audio_stream_idx = 1
                if group.selectedAudioStreamIndex <> invalid
                    audio_stream_idx = group.selectedAudioStreamIndex
                end if

                video_id = group.id
                video = CreateVideoPlayerGroup(video_id, audio_stream_idx)
                if video <> invalid
                    sceneManager.callFunc("pushScene", video)
                end if
            else if btn <> invalid and btn.id = "watched-button"
                movie = group.itemContent
                if movie.watched
                    UnmarkItemWatched(movie.id)
                else
                    MarkItemWatched(movie.id)
                end if
                movie.watched = not movie.watched
            else if btn <> invalid and btn.id = "favorite-button"
                movie = group.itemContent
                if movie.favorite
                    UnmarkItemFavorite(movie.id)
                else
                    MarkItemFavorite(movie.id)
                end if
                movie.favorite = not movie.favorite
            else
                ' If there are no other button matches, check if this is a simple "OK" Dialog & Close if so
                dialog = msg.getRoSGNode()
                if dialog.id = "OKDialog"
                    dialog.unobserveField("buttonSelected")
                    dialog.close = true
                end if
            end if
        else if isNodeEvent(msg, "optionSelected")
            button = msg.getRoSGNode()
            group = sceneManager.callFunc("getActiveScene")
            if button.id = "goto_search"
                ' Exit out of the side panel
                panel = group.findNode("options")
                panel.visible = false
                if group.lastFocus <> invalid
                    group.lastFocus.setFocus(true)
                else
                    group.setFocus(true)
                end if
                group = CreateSearchPage()
                sceneManager.callFunc("pushScene", group)
                group.findNode("SearchBox").findNode("search-input").setFocus(true)
                group.findNode("SearchBox").findNode("search-input").active = true
            else if button.id = "change_server"
                unset_setting("server")
                unset_setting("port")
                SignOut(false)
                sceneManager.callFunc("clearScenes")
                goto app_start
            else if button.id = "sign_out"
                SignOut()
                sceneManager.callFunc("clearScenes")
                goto app_start
            else if button.id = "play_mpeg2"
                playMpeg2 = get_setting("playback.mpeg2")
                if playMpeg2 = "true"
                    playMpeg2 = "false"
                    button.title = tr("MPEG2 Support: Off")
                else
                    playMpeg2 = "true"
                    button.title = tr("MPEG2 Support: On")
                end if
                set_setting("playback.mpeg2", playMpeg2)
            end if
        else if isNodeEvent(msg, "selectSubtitlePressed")
            node = m.scene.focusedChild
            if node.focusedChild <> invalid and node.focusedChild.isSubType("JFVideo")
                trackSelected = selectSubtitleTrack(node.Subtitles, node.SelectedSubtitle)
                if trackSelected <> invalid and trackSelected <> -2
                    changeSubtitleDuringPlayback(trackSelected)
                end if
            end if
        else if isNodeEvent(msg, "state")
            node = msg.getRoSGNode()
            if node.state = "finished"
                node.control = "stop"
                if node.showID = invalid
                    sceneManager.callFunc("popScene")
                else
                    autoPlayNextEpisode(node.id, node.showID)
                end if
            end if
        else if type(msg) = "roDeviceInfoEvent"
            event = msg.GetInfo()
            group = sceneManager.callFunc("getActiveScene")
            if event.exitedScreensaver = true
                sceneManager.callFunc("resetTime")
                if group.subtype() = "Home"
                    currentTime = CreateObject("roDateTime").AsSeconds()
                    group.timeLastRefresh = currentTime
                    group.callFunc("refresh")
                end if
                ' todo: add other screens to be refreshed - movie detail, tv series, episode list etc.
            else
                dlog("Unhandled roDeviceInfoEvent:", "Main")
                print msg.GetInfo()
            end if
        else if type(msg) = "roInputEvent"
            if msg.IsInput()
                info = msg.GetInfo()
                if info.DoesExist("mediatype") and info.DoesExist("contentid")
                    video = CreateVideoPlayerGroup(info.contentId)
                    if video <> invalid
                        sceneManager.callFunc("pushScene", video)
                    else
                        dialog = createObject("roSGNode", "Dialog")
                        dialog.id = "OKDialog"
                        dialog.title = tr("Not found")
                        dialog.message = tr("The requested content does not exist on the server")
                        dialog.buttons = [tr("OK")]
                        m.scene.dialog = dialog
                        m.scene.dialog.observeField("buttonSelected", m.port)
                    end if
                end if
            end if
        else
            dlog("Unhandled " + type(msg), "Main")
            print msg
        end if
    end while



end sub


function LoginFlow(startOver = false as boolean)
    'Collect Jellyfin server and user information
    start_login:

    if get_setting("server") = invalid then startOver = true

    invalidServer = true
    if not startOver
        ' Show Connecting to Server spinner
        dialog = createObject("roSGNode", "ProgressDialog")
        dialog.title = tr("Connecting to Server")
        m.scene.dialog = dialog
        invalidServer = ServerInfo().Error
        dialog.close = true
    end if

    m.serverSelection = "Saved"
    if startOver or invalidServer
      dlog("Main: Get server details")
        SendPerformanceBeacon("AppDialogInitiate") ' Roku Performance monitoring - Dialog Starting
        m.serverSelection = CreateServerGroup()
        SendPerformanceBeacon("AppDialogComplete") ' Roku Performance monitoring - Dialog Closed
        if m.serverSelection = "backPressed"
            dlog("backPressed", "Main")
            m.global.sceneManager.callFunc("clearScenes")
            return false
        end if
        SaveServerList()
    end if

    if get_setting("active_user") = invalid
        SendPerformanceBeacon("AppDialogInitiate") ' Roku Performance monitoring - Dialog Starting
        publicUsers = GetPublicUsers()
        if publicUsers.count()
            publicUsersNodes = []
            for each item in publicUsers
                user = CreateObject("roSGNode", "PublicUserData")
                user.id = item.Id
                user.name = item.Name
                if item.PrimaryImageTag <> invalid
                    user.ImageURL = UserImageURL(user.id, { "tag": item.PrimaryImageTag })
                end if
                publicUsersNodes.push(user)
            end for
            userSelected = CreateUserSelectGroup(publicUsersNodes)
            if userSelected = "backPressed"
                SendPerformanceBeacon("AppDialogComplete") ' Roku Performance monitoring - Dialog Closed
                return LoginFlow(true)
            else
                'Try to login without password. If the token is valid, we're done
                get_token(userSelected, "")
                if get_setting("active_user") <> invalid
                    m.user = AboutMe()
                    LoadUserPreferences()
                    LoadUserAbilities(m.user)
                    SendPerformanceBeacon("AppDialogComplete") ' Roku Performance monitoring - Dialog Closed
                    return true
                end if
            end if
        else
            userSelected = ""
        end if
        passwordEntry = CreateSigninGroup(userSelected)
        SendPerformanceBeacon("AppDialogComplete") ' Roku Performance monitoring - Dialog Closed
        if passwordEntry = "backPressed"
            m.global.sceneManager.callFunc("clearScenes")
            return LoginFlow(true)
        end if
    end if

    m.user = AboutMe()
    if m.user = invalid or m.user.id <> get_setting("active_user")
        dlog("Login failed, restart flow", "Main")
        unset_setting("active_user")
        goto start_login
    end if

    LoadUserPreferences()
    LoadUserAbilities(m.user)
    m.global.sceneManager.callFunc("clearScenes")

    'Send Device Profile information to server
    body = getDeviceCapabilities()
    req = APIRequest("/Sessions/Capabilities/Full")
    req.SetRequest("POST")
    postJson(req, FormatJson(body))
    return true
end function

sub SaveServerList()
    'Save off this server to our list of saved servers for easier navigation between servers
    server = get_setting("server")
    saved = get_setting("saved_servers")
    if server <> invalid
        server = LCase(server)'Saved server data is always lowercase
    end if
    entryCount = 0
    addNewEntry = true
    savedServers = { serverList: [] }
    if saved <> invalid
        savedServers = ParseJson(saved)
        entryCount = savedServers.serverList.Count()
        if savedServers.serverList <> invalid and entryCount > 0
            for each item in savedServers.serverList
                if item.baseUrl = server
                    addNewEntry = false
                    exit for
                end if
            end for
        end if
    end if

    if addNewEntry
        if entryCount = 0
            set_setting("saved_servers", FormatJson({ serverList: [{ name: m.serverSelection, baseUrl: server, iconUrl: "pkg:/images/logo-icon120.jpg", iconWidth: 120, iconHeight: 120 }] }))
        else
            savedServers.serverList.Push({ name: m.serverSelection, baseUrl: server, iconUrl: "pkg:/images/logo-icon120.jpg", iconWidth: 120, iconHeight: 120 })
            set_setting("saved_servers", FormatJson(savedServers))
        end if
    end if
end sub

sub DeleteFromServerList(urlToDelete)
    saved = get_setting("saved_servers")
    if urlToDelete <> invalid
        urlToDelete = LCase(urlToDelete)
    end if
    if saved <> invalid
        savedServers = ParseJson(saved)
        newServers = { serverList: [] }
        for each item in savedServers.serverList
            if item.baseUrl <> urlToDelete
                newServers.serverList.Push(item)
            end if
        end for
        set_setting("saved_servers", FormatJson(newServers))
    end if
end sub

sub RunScreenSaver()
    dlog( "Starting screensaver...", "Main")
    screen = createObject("roSGScreen")
    m.port = createObject("roMessagePort")
    screen.setMessagePort(m.port)

    screen.createScene("Screensaver")
    screen.Show()

    while true
        msg = wait(8000, m.port)
        if msg <> invalid
            msgType = type(msg)
            if msgType = "roSGScreenEvent"
                if msg.isScreenClosed() then return
            end if
        end if
    end while

end sub

' Roku Performance monitoring
sub SendPerformanceBeacon(signalName as string)
    if m.global.app_loaded = false
        m.scene.signalBeacon(signalName)
    end if
end sub
