<#> AUTHOR: Jonathon D. Phillips
        Twitter/X: LiyabilityJP
        Discord/Twitch/GitHub/Epic: Liyability
        Organization: Reliyability Software LLC

<#> CONTRIBUTORS: []

using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/Teams }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

PlayerCounterToolTip<localizes>: message = "Player counter must include spectators and cannot use volume"

custom_playspace := class<concrete>:
    @editable{ ToolTip := PlayerCounterToolTip }
    PlayerCounter: player_counter_device = player_counter_device{}

    var MaybePlayspace<private>: ?fort_playspace = false
    var PlayspacePlayers<private>: []player = array{}

    JoinInProgressEvent: event(player) = event(player){}
    LeaveInProgressEvent: event(player) = event(player){}

    Init(InCreativeDevice: creative_device): void = spawn{ Self.InitLoop(InCreativeDevice) }

    InitLoop<private>(InCreativeDevice: creative_device)<suspends>: void =
        Playspace := InCreativeDevice.GetPlayspace()
        set Self.MaybePlayspace = option. Playspace

        for (Player : Playspace.GetPlayers()). Player.HandleJoinInProgress()

        sync:
            loop. Self.PlayerCounter.CountedEvent.Await().MaybeHandleJoinInProgressAfterMovement()
            loop. Self.PlayerCounter.RemovedEvent.Await().MaybeHandleLeaveInProgress()

    GetActivePlayer<public>()<transacts><decides>: player =
        var MaybeActivePlayer: ?player = false
        for (Player : Self.GetPlayers(), Player.IsActive[]). set MaybeActivePlayer = option. Player
        MaybeActivePlayer?

    GetActivePlayerByTeamIndex<public>(InIndex: int)<transacts><decides>: []player =
        Self.GetActivePlayersByTeamIndex[0]

    GetActivePlayersByTeamIndex<public>(InTeamIndex: int)<transacts><decides>: []player =
        Playspace := Self.MaybePlayspace?
        TeamCollection := Playspace.GetTeamCollection()
        Team := TeamCollection.GetTeams()[InTeamIndex]
        AgentsOnTeam := TeamCollection.GetAgents[Team]
        for (Agent : AgentsOnTeam, Player := player[Agent], Player.IsActive[]). Player 

    GetFortCharacters()<transacts>: []fort_character =
        var FortCharacters: []fort_character = array{}
        for (Player : Self.PlayspacePlayers, FortCharacter := Player.GetFortCharacter[]). set FortCharacters += array{ FortCharacter }
        FortCharacters

    GetPlayers()<transacts>: []player = Self.PlayspacePlayers

    GetPlayersByTeamIndex(InTeamIndex: int)<transacts><decides>: []player =
        Playspace := Self.MaybePlayspace?
        TeamCollection := Playspace.GetTeamCollection()
        Team := TeamCollection.GetTeams()[InTeamIndex]
        AgentsOnTeam := TeamCollection.GetAgents[Team]
        for (Agent : AgentsOnTeam). player[Agent]

    GetTeamCollection()<transacts><decides>: fort_team_collection =
        Playspace := Self.MaybePlayspace?
        Playspace.GetTeamCollection() 

    GetTeams()<transacts><decides>: []team =
        Playspace := Self.MaybePlayspace?
        Playspace.GetTeamCollection().GetTeams()

    GetTeamByAgent(InAgent: agent)<transacts><decides>: team =
        Playspace := Self.MaybePlayspace?
        Playspace.GetTeamCollection().GetTeam[InAgent]

    GetTeamByIndex(InIndex: int)<transacts><decides>: team =
        Self.GetTeams[][InIndex]

    GetTeamByFortCharacter(InFortCharacter: fort_character)<transacts><decides>: team =
        InAgent := InFortCharacter.GetAgent[]
        GetTeamByAgent[InAgent]

    AddToTeamWithIndex(InAgent: agent, InTeamIndex: int)<transacts><decides>: void =
        Playspace := Self.MaybePlayspace?
        Team := Self.GetTeamByAgent[InAgent]
        Playspace.GetTeamCollection().AddToTeam[InAgent, Team]

    IsOnTeamWithIndex(InAgent: agent, InTeamIndex: int)<transacts><decides>: void =
        Playspace := Self.MaybePlayspace?
        TeamCollection := Playspace.GetTeamCollection()
        Teams := Playspace.GetTeamCollection().GetTeams()
        TeamByIndex := Teams[InTeamIndex]
        TeamCollection.IsOnTeam[InAgent, TeamByIndex]

    (InAgent: agent).HandleJoinInProgress<private>(): void =
        if (InPlayer := player[InAgent]):
            Self.PlayspacePlayers.RemoveAllElements(InPlayer)
            set Self.PlayspacePlayers += array{ InPlayer }
            Self.JoinInProgressEvent.Signal(InPlayer)

    (InAgent: agent).MaybeHandleJoinInProgress<private>(): void =
        if:
            InPlayer := player[InAgent]
            InPlayer.IsActive[]
            not Self.PlayspacePlayers.Find[InAgent]
        then:
            InPlayer.HandleJoinInProgress()

    (InAgent: agent).MaybeHandleJoinInProgressAfterMovement<private>(): void =
        if (not Self.PlayspacePlayers.Find[InAgent]):
            if (InFortCharacter := InAgent.GetFortCharacter[]):
                spawn{ InFortCharacter.MonitorMovementLoop(InAgent) }

    (InAgent: agent).MaybeHandleLeaveInProgress<private>(): void =
        if (InPlayer := player[InAgent]). spawn. InPlayer.HandleLeaveInProgress()

    (InFortCharacter: fort_character).MonitorMovementLoop<private>(InAgent: agent)<suspends>: void =
        OriginalTranslation := InFortCharacter.GetTransform().Translation
        OriginalX := OriginalTranslation.X
        OriginalY := OriginalTranslation.Y
        OriginalZ := OriginalTranslation.Z
        loop:
            Sleep(0.25)
            CurrentTranslation := InFortCharacter.GetTransform().Translation
            CurrentX := CurrentTranslation.X
            CurrentY := CurrentTranslation.Y
            CurrentZ := CurrentTranslation.Z
            if ((OriginalX <> CurrentX) or (OriginalY <> CurrentY) or (OriginalZ <> CurrentZ)). break
        InAgent.HandleJoinInProgress()

    (InPlayer: player).HandleLeaveInProgress<private>()<suspends>: void =
        var Iteration: int = 0
        loop:
            if (InPlayer.IsActive[] and Iteration < 40):
                set Iteration += 1
                Sleep(0.25)
            else. break
        set Self.PlayspacePlayers = Self.PlayspacePlayers.RemoveAllElements(InPlayer)
        Self.LeaveInProgressEvent.Signal(InPlayer)
