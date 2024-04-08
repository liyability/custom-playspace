<#> AUTHOR: Jonathon D. Phillips
        Twitter/X: LiyabilityJP
        Discord/Twitch/GitHub/Epic: syntaxErr0rz
        Organization: Reliyability Software LLC

<#> CONTRIBUTORS: []

# IMPORTS
using { /Fortnite.com/Characters }
using { /Fortnite.com/Devices }
using { /Fortnite.com/Playspaces }
using { /Fortnite.com/Teams }
using { /Verse.org/Simulation }
using { /UnrealEngine.com/Temporary/Diagnostics }
using { /UnrealEngine.com/Temporary/SpatialMath }

# TOOLTIPS
MaybePlayerCounterToolTip<localizes>: message = "Player counter must include spectators and cannot use volume"

MaybeJoinInProgressTriggerToolTip<localizes>: message = "You can add a trigger to pass join in progress agents to other devices"

MaybeLeaveInProgressTriggerToolTip<localizes>: message = "You can add a trigger to pass leave in progress agents to other devices"

PulseRateToolTip<localizes>: message = "PULSE_RATE is the rate in which the Playspace is scraped for join/leave in progress Agents"

# CUSTOM CONCRETE CLASS
custom_playspace := class<concrete>:

    # OPTIONAL EDITABLES
    @editable
    MaybePlayerSpawners: ?[]player_spawner_device = false

    @editable
    MaybeTeamSettingsDevices: ?[]team_settings_and_inventory_device = false

    @editable{ ToolTip := MaybePlayerCounterToolTip }
    MaybePlayerCounter: ?player_counter_device = false

    @editable
    MaybeMutatorZone: ?mutator_zone_device = false

    @editable
    MaybeVolumeDevice: ?volume_device = false

    @editable{ ToolTip := MaybeJoinInProgressTriggerToolTip }
    MaybeJoinInProgressTrigger: ?trigger_device = false

    @editable{ ToolTip := MaybeLeaveInProgressTriggerToolTip }
    MaybeLeaveInProgressTrigger: ?trigger_device = false

    # CONFIGURABLE PULSE CHECK RATE
    @editable{ ToolTip := PulseRateToolTip }
    PULSE_CHECK_RATE: float = 0.5

    # MAINTAINED ARRAY OF AGENTS IN PLAYSPACE
    var PlayspacePlayers<private>: []player = array{}

    # CUSTOM EVENTS
    JoinInProgressEvent: event(agent) = event(agent){}

    LeaveInProgressEvent: event(agent) = event(agent){}

    # INIT FUNCTIONALITY
    Init(InCreativeDevice: creative_device): void = spawn{ Self.InitLoop(InCreativeDevice) }

    InitLoop(InCreativeDevice: creative_device)<suspends>: void =
        Playspace := InCreativeDevice.GetPlayspace()

        # JOIN IN PROGRESS CHECKS
        for (Player : Playspace.GetPlayers()). Player.MaybeHandleJoinInProgress()
        if (PlayerSpawners := Self.MaybePlayerSpawners?):
            for (PlayerSpawner : PlayerSpawners). spawn{ PlayerSpawner.HandleJoinInProgressLoop() }
        if (TeamSettingsDevices := Self.MaybeTeamSettingsDevices?):
            for (TeamSettingsDevice : TeamSettingsDevices). spawn{ TeamSettingsDevice.HandleJoinInProgressLoop() }
        sync:
            loop:
                Playspace.PlayerAddedEvent().Await().MaybeHandleJoinInProgress()
            loop:
                Sleep(Self.PULSE_CHECK_RATE)
                for (Player : Playspace.GetPlayers()):
                    if (Agent := agent[Player]). Agent.MaybeHandleJoinInProgress()
            loop:
                if (PlayerCounter := Self.MaybePlayerCounter?):
                    PlayerCounter.CountedEvent.Await().MaybeHandleJoinInProgressAfterMovement()
                else. break
            loop:
                if (MutatorZone := Self.MaybeMutatorZone?):
                    MutatorZone.AgentEntersEvent.Await().MaybeHandleJoinInProgress()
                else. break
            loop:
                if (VolumeDevice := Self.MaybeVolumeDevice?):
                    VolumeDevice.AgentEntersEvent.Await().MaybeHandleJoinInProgress()
                else. break
            # LEAVE IN PROGRESS CHECKS
            loop:
                Playspace.PlayerRemovedEvent().Await().MaybeHandleLeaveInProgress()
            loop:
                if (PlayerCounter := Self.MaybePlayerCounter?):
                    PlayerCounter.RemovedEvent.Await().MaybeHandleLeaveInProgress()
                else. break
            loop:
                Sleep(Self.PULSE_CHECK_RATE)
                for (Agent : Self.PlayspacePlayers). Agent.MaybeHandleLeaveInProgress()

    # GETTERS
    GetAgents(): []agent =
        var Agents: []agent = array{}
        for (Player : Self.PlayspacePlayers, Agent := agent[Player]). set Agents += array{ Agent }
        Agents

    GetAgentsByTeamIndex(InTeamIndex: int, InCreativeDevice: creative_device)<transacts><decides>: []agent =
        TeamCollection := InCreativeDevice.GetPlayspace().GetTeamCollection()
        Team := TeamCollection.GetTeams()[InTeamIndex]
        TeamCollection.GetAgents[Team]

    GetFortCharacters(): []fort_character =
        var FortCharacters: []fort_character = array{}
        for (Player : Self.PlayspacePlayers, FortCharacter := Player.GetFortCharacter[]). set FortCharacters += array{ FortCharacter }
        FortCharacters

    GetPlayers(): []player = Self.PlayspacePlayers

    GetTeamCollection(InCreativeDevice: creative_device): fort_team_collection = InCreativeDevice.GetPlayspace().GetTeamCollection() 

    GetTeams(InCreativeDevice: creative_device): []team = InCreativeDevice.GetPlayspace().GetTeamCollection().GetTeams()

    GetTeamByAgent(InAgent: agent, InCreativeDevice: creative_device)<transacts><decides>: team =
        InCreativeDevice.GetPlayspace().GetTeamCollection().GetTeam[InAgent]

    GetTeamByFortCharacter(InFortCharacter: fort_character, InCreativeDevice: creative_device)<transacts><decides>: team =
        InAgent := InFortCharacter.GetAgent[]
        GetTeamByAgent[InAgent, InCreativeDevice]

    # METHODS
    AddToTeamWithIndex(InAgent: agent, InTeamIndex: int, InCreativeDevice: creative_device)<transacts><decides>: void =
        Team := Self.GetTeamByAgent[InAgent, InCreativeDevice]
        InCreativeDevice.GetPlayspace().GetTeamCollection().AddToTeam[InAgent, Team]

    IsOnTeamWithIndex(InAgent: agent, InTeamIndex: int, InCreativeDevice: creative_device)<transacts><decides>: void =
        Team := Self.GetTeamByAgent[InAgent, InCreativeDevice]
        InCreativeDevice.GetPlayspace().GetTeamCollection().IsOnTeam[InAgent, Team]

    # INTERNAL EXTENSION METHODS
    (InAgent: agent).HandleJoinInProgress<private>(): void =
        if (InPlayer := player[InAgent]):
            set Self.PlayspacePlayers += array{ InPlayer }
            Self.JoinInProgressEvent.Signal(InAgent)
            if (JoinInProgressTrigger := MaybeJoinInProgressTrigger?). JoinInProgressTrigger.Trigger(InAgent)

    (InAgent: agent).MaybeHandleJoinInProgress<private>(): void =
        if (not Self.PlayspacePlayers.Find[InAgent]). InAgent.HandleJoinInProgress()

    (InAgent: agent).MaybeHandleJoinInProgressAfterMovement<private>(): void =
        if (not Self.PlayspacePlayers.Find[InAgent]):
            if (InFortCharacter := InAgent.GetFortCharacter[]):
                spawn{ InFortCharacter.MonitorMovementLoop(InAgent) }

    (InAgent: agent).HandleLeaveInProgress<private>(): void =
        Self.PlayspacePlayers.RemoveAllElements(InAgent)
        Self.LeaveInProgressEvent.Signal(InAgent)
        if (LeaveInProgressTrigger := MaybeLeaveInProgressTrigger?). LeaveInProgressTrigger.Trigger(InAgent)

    (InAgent: agent).MaybeHandleLeaveInProgress<private>(): void =
        if (InPlayer := player[InAgent], not InPlayer.IsActive[]). InAgent.HandleLeaveInProgress()

    (InFortCharacter: fort_character).MonitorMovementLoop<private>(InAgent: agent)<suspends>: void =
        OriginalTranslation := InFortCharacter.GetTransform().Translation
        loop:
            Sleep(0.01)
            if (Distance(InFortCharacter.GetTransform().Translation, OriginalTranslation) <> 0.0). break
        InAgent.HandleJoinInProgress()

    (InPlayerSpawner: player_spawner_device).HandleJoinInProgressLoop<private>()<suspends>: void =
        loop{ InPlayerSpawner.SpawnedEvent.Await().MaybeHandleJoinInProgress() }

    (InTeamSettingsDevice: team_settings_and_inventory_device).HandleJoinInProgressLoop<private>()<suspends>: void =
        loop{ InTeamSettingsDevice.TeamMemberSpawnedEvent.Await().MaybeHandleJoinInProgress() }