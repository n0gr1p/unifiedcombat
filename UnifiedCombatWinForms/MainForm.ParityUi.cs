namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private GroupBox _grpHealer = null!;
    private GroupBox _grpCombat = null!;
    private GroupBox _grpBehavior = null!;
    private GroupBox _grpVisuals = null!;
    private CheckBox _chkWeaponskill = null!;
    private CheckBox _chkAftermath = null!;
    private CheckBox _chkAbility = null!;
    private CheckBox _chkPuller = null!;
    private ComboBox _wsCombo = null!;
    private ComboBox _wsModeCombo = null!;
    private NumericUpDown _wsMinimumTp = null!;
    private ComboBox _aftermathCombo = null!;
    private ComboBox _pullerCombo = null!;
	private ComboBox _pullerLeashSource = null!;
    private TextBox _pullerEngageRange = null!;
	private Button _campSet = null!;
	private Button _campClear = null!;
	private Label _campStatus = null!;
    private ComboBox _fightLeaderCombo = null!;
    private ComboBox _partyFollowCombo = null!;
    private Label _partyFollowModeWarning = null!;
    private TextBox _pfFollowMinYalms = null!;
    private TextBox _pfFollowMaxYalms = null!;
    private TextBox _pfFightFollowMinYalms = null!;
    private TextBox _pfFightFollowHoldS = null!;
	private ComboBox _nyzulCoordinatorCombo = null!;
	private ComboBox _nyzulAnchorCombo = null!;
	private ComboBox _nyzulParkerCombo = null!;
	private ListBox _nyzulParkingList = null!;
	private Button _nyzulParkerAdd = null!;
	private Button _nyzulParkerRemove = null!;
	private Button _nyzulParkerUp = null!;
	private Button _nyzulParkerDown = null!;
    private ComboBox _defProviderCombo = null!;
    private ComboBox _abilityPickCombo = null!;
    private ListBox _abilityList = null!;
    private Button _btnAbilityAdd = null!;
    private Button _btnAbilityRemove = null!;
    private Button _btnAbilityUp = null!;
    private Button _btnAbilityDown = null!;
    private TextBox _defCrit = null!;
    private TextBox _defMed = null!;
    private TextBox _defHealMinTier = null!;
    private TextBox _defHealMaxTier = null!;
    private TextBox _defHealMinMissingHp = null!;
    private CheckBox _defHealIgnoreTrusts = null!;
    private TextBox _defOverwrite = null!;
    private TextBox _defBuffs = null!;
    private TextBox _defTargetedBuffs = null!;
    private GroupBox _grpFightLeader = null!;
    private GroupBox _grpAddPri = null!;
    private ListBox _addPriList = null!;
    private TextBox _addPriName = null!;
    private Button _addPriByName = null!;
    private Button _addPriCurTarget = null!;
    private Button _addPriRemove = null!;
    private Button _addPriUp = null!;
    private Button _addPriDown = null!;
    private GroupBox _grpSleepSpells = null!;
    private ListBox _sleepSpellList = null!;
    private TextBox _sleepSpellName = null!;
    private TextBox _sleepMaxTargetRange = null!;
    private Button _sleepSpellSetOnly = null!;
    private Button _sleepSpellAdd = null!;
    private Button _sleepSpellRemove = null!;
    private Button _sleepSpellClear = null!;
    private Button _sleepSpellUp = null!;
    private Button _sleepSpellDown = null!;
    private GroupBox _grpPartner = null!;
    private ListBox _partnerList = null!;
    private TextBox _partnerName = null!;
    private Button _partnerByName = null!;
    private Button _partnerCurTarget = null!;
    private Button _partnerRemove = null!;
    private GroupBox _grpIgnore = null!;
    private ListBox _ignoreList = null!;
    private TextBox _ignoreName = null!;
    private Button _ignoreByName = null!;
    private Button _ignoreCurTarget = null!;
    private Button _ignoreRemove = null!;
    private GroupBox _grpTargetIgn = null!;
    private ListBox _targetIgnList = null!;
    private TextBox _targetIgnName = null!;
    private Button _targetIgnByName = null!;
    private Button _targetIgnCurTarget = null!;
    private Button _targetIgnRemove = null!;
    private Button _btnSave = null!;
    private Button _btnToggleEngine = null!;
    private Button _btnReloadAddon = null!;
    private CheckBox _spUsePrediction = null!;
    private TextBox _spBandMin = null!;
    private TextBox _spBandMax = null!;
    private TextBox _spModelSizeFloor = null!;
    private TextBox _spLookahead = null!;
    private TextBox _spAnchorInvalidTicks = null!;
    private TextBox _spEmergencyMargin = null!;
    private TextBox _spSwitchMargin = null!;
    private TextBox _spArrivalTolerance = null!;
    private CheckBox _formationEnabled = null!;
    private ComboBox _formationEncounter = null!;
    private ComboBox _formationRole = null!;
    private ComboBox _formationTankName = null!;
    private CheckedListBox _formationRequiredParty = null!;
    private NumericUpDown _formationCaptureStable = null!;
    private NumericUpDown _formationCaptureTolerance = null!;
    private NumericUpDown _formationSafeRadius = null!;
    private NumericUpDown _formationTankAcceptRadius = null!;
    private NumericUpDown _formationTankReturnRadius = null!;
    private NumericUpDown _formationDpsFlankAngle = null!;
    private NumericUpDown _formationDpsMeleeRadius = null!;
    private NumericUpDown _formationDpsPositionTolerance = null!;
    private NumericUpDown _formationHealerPreferredRadius = null!;
    private NumericUpDown _formationHealerMinimumBossDistance = null!;
    private NumericUpDown _formationHealerMaximumPartyRange = null!;
    private NumericUpDown _formationHealerConeHalfAngle = null!;
    private NumericUpDown _formationHealerConeSafetyMargin = null!;
    private NumericUpDown _formationHealerSampleStep = null!;
    private TableLayoutPanel _formationConfigPanel = null!;
    private Label _formationValidation = null!;
    private Button _formationEnableOwnership = null!;
    private TabControl _settingsTabs = null!;
    private TabPage _tabGeo = null!;
    private TabPage _tabSummoner = null!;
    private TabPage _tabCor = null!;
    private TabPage _tabBrd = null!;
    private CheckBox _geoEnabled = null!;
    private TextBox _geoSpell = null!;
    private TextBox _indiSpell = null!;
    private ComboBox _geoTargetKind = null!;
    private TextBox _geoTargetName = null!;
    private ComboBox _geoOrdering = null!;
    private CheckBox _geoRequireCamp = null!;
    private NumericUpDown _geoCampTolerance = null!;
    private CheckBox _geoEntrustEnabled = null!;
    private TextBox _geoEntrustSpell = null!;
    private TextBox _geoEntrustTarget = null!;
    private CheckBox _geoUseBlaze = null!;
    private CheckBox _geoUseEcliptic = null!;
    private CheckBox _geoUseLifeCycle = null!;
    private NumericUpDown _geoLifeCycleHpp = null!;
    private CheckBox _geoReplaceOutOfPosition = null!;
    private CheckBox _geoEnemyRequiresCampRadius = null!;
    private NumericUpDown _geoMaxCampDistance = null!;
    private Label _geoRuntimeStatus = null!;
    private Label _geoHelp = null!;
    private CheckBox _campPullEnabled = null!;
    private ComboBox _campPullActionType = null!;
    private TextBox _campPullActionName = null!;
    private TextBox _campPullTargets = null!;
    private ComboBox _campPullMatchMode = null!;
    private NumericUpDown _campPullMaxActive = null!;
    private NumericUpDown _campPullReplenishHpp = null!;
    private NumericUpDown _campPullLeash = null!;
    private NumericUpDown _campPullMaxZ = null!;
    private NumericUpDown _campPullRangeRatio = null!;
    private NumericUpDown _campPullSettle = null!;
    private NumericUpDown _campPullReactionTimeout = null!;
    private NumericUpDown _campPullRetryLimit = null!;
    private NumericUpDown _campPullRetryWindow = null!;
    private NumericUpDown _campPullCooldown = null!;
    private NumericUpDown _campPullArrival = null!;
    private Label _campPullRuntimeStatus = null!;
    private Label _campPullHelp = null!;
    private CheckBox _summonerEnabled = null!;
    private ComboBox _summonerAvatar = null!;
    private CheckBox _summonerAvatarFavor = null!;
    private CheckBox _summonerWardEnabled = null!;
    private ComboBox _summonerWardAction = null!;
    private CheckBox _summonerEngage = null!;
    private CheckBox _summonerRageEnabled = null!;
    private ComboBox _summonerRageAction = null!;
    private CheckBox _summonerRageTargetHppAboveEnabled = null!;
    private NumericUpDown _summonerRageTargetHppAbove = null!;
    private CheckBox _summonerRagePetTpAboveEnabled = null!;
    private NumericUpDown _summonerRagePetTpAbove = null!;
    private Label _summonerValidation = null!;
    private CheckBox _reactionEnabled = null!;
    private ListBox _reactionRuleList = null!;
    private ComboBox _reactionTriggerCombo = null!;
    private TextBox _reactionName = null!;
    private ComboBox _reactionResponseCombo = null!;
    private Button _reactionAdd = null!;
    private Button _reactionRemove = null!;
    private Button _reactionUp = null!;
    private Button _reactionDown = null!;
    private readonly List<ReactionRuleRow> _reactionRules = [];
    private ComboBox _corRoll1Combo = null!;
    private ComboBox _corRoll2Combo = null!;
    private CheckBox _corCrookedRoll1 = null!;
    private CheckBox _corCrookedRoll2 = null!;
    private CheckBox _corElevens = null!;
    private CheckBox _corLuzafRangeOverride = null!;
    private FlowLayoutPanel _corRangePartyPanel = null!;
    private CheckBox _brdEnabled = null!;
    private ListBox _brdSongList = null!;
    private ComboBox _brdSongCombo = null!;
    private Button _brdSongAdd = null!;
    private Button _brdSongRemove = null!;
    private Button _brdSongUp = null!;
    private Button _brdSongDown = null!;
    private ListBox _brdDummyList = null!;
    private ComboBox _brdDummyCombo = null!;
    private Button _brdDummyAdd = null!;
    private Button _brdDummyRemove = null!;
    private Button _brdDummyUp = null!;
    private Button _brdDummyDown = null!;
    private CheckBox _brdUseNitro = null!;
	private CheckBox _brdUseSoulVoice = null!;
    private CheckBox _brdUseClarion = null!;
    private CheckBox _brdUseMarcato = null!;
    private ComboBox _brdMarcatoSong = null!;
	private NumericUpDown _brdRecoveryRangeYalms = null!;
	private TextBox _brdRecoveryIgnoreNames = null!;
	private CheckBox _brdRepositionForPartySongs = null!;
	private TextBox _brdTargetedSongs = null!;
    private Label _pathFileValue = null!;
    private Label _pathRouteTypeValue = null!;
    private Label _pathDistanceValue = null!;
    private Label _pathPointCountValue = null!;
    private TextBox _pathPartyGateYalms = null!;
    private TextBox _pathResumeIndexWindow = null!;
    private ListBox _pathHunterList = null!;
    private TextBox _pathHunterName = null!;
    private TextBox _pathHunterMaxZDelta = null!;
    private TextBox _pathHunterMaxTargetRange = null!;
    private TextBox _pathHunterClaimTimeout = null!;
    private TextBox _pathHunterIgnoreCooldown = null!;
    private ComboBox _pathPullActionType = null!;
    private ComboBox _pathPullActionName = null!;
    private Button _pathHunterAdd = null!;
    private Button _pathHunterRemove = null!;
    private ListBox _tankEnmityList = null!;
    private ComboBox _tankEnmityTypeCombo = null!;
    private ComboBox _tankEnmityNameCombo = null!;
    private Button _tankEnmityAdd = null!;
    private Button _tankEnmityRemove = null!;
    private Button _tankEnmityUp = null!;
    private Button _tankEnmityDown = null!;

    private void BuildParityEditor(Panel host, FlowLayoutPanel sessionActionsFooter)
    {
        host.Padding = new Padding(8);
        var root = new TableLayoutPanel
        {
            Dock = DockStyle.Top,
            AutoSize = true,
            ColumnCount = 1,
            RowCount = 2,
        };
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        root.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        host.Controls.Add(root);
        host.Resize += (_, _) => root.Width = Math.Max(400, host.ClientSize.Width - 16);

        var top = new TableLayoutPanel
        {
            AutoSize = true,
            ColumnCount = 4,
            RowCount = 1,
            Dock = DockStyle.Top,
            Width = host.ClientSize.Width,
        };
        for (var i = 0; i < 4; i++)
        {
            top.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 25f));
        }

        _grpHealer = CreateBoolCard("Healer / Defensive", HubUiConstants.HealerCardKeys);
        _grpCombat = CreateBoolCard("Combat Engine", HubUiConstants.CombatCardKeys);
        _grpBehavior = CreateBoolCard("Behavior / Legacy", HubUiConstants.BehaviorCardKeys);
        _grpVisuals = CreateBoolCard("Display / Misc", HubUiConstants.VisualsCardKeys);
        top.Controls.Add(_grpHealer, 0, 0);
        top.Controls.Add(_grpCombat, 1, 0);
        top.Controls.Add(_grpBehavior, 2, 0);
        top.Controls.Add(_grpVisuals, 3, 0);
        root.Controls.Add(top, 0, 0);

        var form = new GroupBox
        {
            Text = "Settings (selected session)",
            Padding = new Padding(8),
            Dock = DockStyle.Top,
            AutoSize = true,
        };
        var g = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 1,
            Padding = new Padding(0),
        };
        g.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        var gRow = 0;

        // Top split: combat / abilities (left) | defensive healer fields (right)
        var topSplit = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 2,
            Padding = new Padding(0, 0, 0, 4),
        };
        topSplit.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50f));
        topSplit.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50f));
        topSplit.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        var leftCol = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            Padding = new Padding(0, 0, 8, 0),
        };
        leftCol.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
        leftCol.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        var lr = 0;

        var wsLab = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        _chkWeaponskill = MkCtx("weaponskill_active");
        wsLab.Controls.Add(_chkWeaponskill);
        leftCol.Controls.Add(wsLab, 0, lr);
        _wsCombo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDown,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(120, 0),
        };
        _wsCombo.SelectedIndexChanged += (_, _) => OnWsSelected();
        _wsCombo.DropDown += (_, _) =>
        {
            var sid = _selectedSid;
            if (!string.IsNullOrWhiteSpace(sid))
            {
                EnsureOptionsHydrated(sid);
            }
        };
        leftCol.Controls.Add(_wsCombo, 1, lr);
        lr++;

        leftCol.Controls.Add(new Label { Text = "WS mode", AutoSize = true, Anchor = AnchorStyles.Left }, 0, lr);
        _wsModeCombo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(120, 0),
        };
        _wsModeCombo.Items.Add("Smart");
        _wsModeCombo.Items.Add("Primary Only (No SC)");
        _wsModeCombo.SelectedIndex = 0;
        _wsModeCombo.SelectedIndexChanged += (_, _) => OnWsModeSelected();
        leftCol.Controls.Add(_wsModeCombo, 1, lr);
        lr++;

        leftCol.Controls.Add(new Label { Text = "Minimum WS TP", AutoSize = true, Anchor = AnchorStyles.Left }, 0, lr);
        _wsMinimumTp = new NumericUpDown
        {
            Minimum = 1000,
            Maximum = 3000,
            Increment = 100,
            Value = 1000,
            DecimalPlaces = 0,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(120, 0),
        };
        _wsMinimumTp.ValueChanged += (_, _) => OnWsMinimumTpChanged();
        leftCol.Controls.Add(_wsMinimumTp, 1, lr);
        lr++;

        _chkAftermath = MkCtx("aftermath_enabled");
        leftCol.Controls.Add(_chkAftermath, 0, lr);
        _aftermathCombo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDown,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(120, 0),
        };
        _aftermathCombo.SelectedIndexChanged += (_, _) => OnAftermathWsSelected();
        _aftermathCombo.DropDown += (_, _) =>
        {
            var sid = _selectedSid;
            if (!string.IsNullOrWhiteSpace(sid))
            {
                EnsureOptionsHydrated(sid);
            }
        };
        leftCol.Controls.Add(_aftermathCombo, 1, lr);
        lr++;

        var abPick = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        _chkAbility = MkCtx("ability_active");
        leftCol.Controls.Add(_chkAbility, 0, lr);
        _abilityPickCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDown, Width = 220 };
        _abilityPickCombo.DropDown += (_, _) =>
        {
            var sid = _selectedSid;
            if (!string.IsNullOrWhiteSpace(sid))
            {
                EnsureOptionsHydrated(sid);
            }
        };
        _btnAbilityAdd = new Button { Text = "Add", AutoSize = true };
        _btnAbilityAdd.Click += (_, _) => AddAbility();
        abPick.Controls.Add(_abilityPickCombo);
        abPick.Controls.Add(_btnAbilityAdd);
        leftCol.Controls.Add(abPick, 1, lr);
        lr++;

        _abilityList = new ListBox
        {
            Height = 120,
            IntegralHeight = false,
            Dock = DockStyle.Top,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
        };
        _abilityList.SelectedIndexChanged += (_, _) => _abilityInteractionUtc = DateTime.UtcNow;
        leftCol.Controls.Add(_abilityList, 0, lr);
        leftCol.SetColumnSpan(_abilityList, 2);
        lr++;

        var abBtns = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        _btnAbilityRemove = new Button { Text = "Remove", AutoSize = true };
        _btnAbilityRemove.Click += (_, _) => RemoveAbility();
        _btnAbilityUp = new Button { Text = "Up", AutoSize = true };
        _btnAbilityUp.Click += (_, _) => MoveAbilityUp();
        _btnAbilityDown = new Button { Text = "Down", AutoSize = true };
        _btnAbilityDown.Click += (_, _) => MoveAbilityDown();
        abBtns.Controls.AddRange(new Control[] { _btnAbilityRemove, _btnAbilityUp, _btnAbilityDown });
        leftCol.Controls.Add(abBtns, 0, lr);
        leftCol.SetColumnSpan(abBtns, 2);
        lr++;

        var pull = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        _chkPuller = MkCtx("puller");
        pull.Controls.Add(_chkPuller);
		_pullerLeashSource = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 80 };
		_pullerLeashSource.Items.AddRange(new object[] { "Player", "Camp" });
		_pullerLeashSource.SelectedIndexChanged += (_, _) => OnPullerLeashSourceChanged();
		pull.Controls.Add(_pullerLeashSource);
        _pullerCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 };
        _pullerCombo.SelectedIndexChanged += (_, _) => OnPullerSelected();
        pull.Controls.Add(_pullerCombo);
        pull.Controls.Add(new Label { Text = "Engage range", AutoSize = true, Padding = new Padding(8, 4, 0, 0) });
        _pullerEngageRange = new TextBox { Width = 52 };
        _pullerEngageRange.Leave += (_, _) => OnPullerEngageRangeChanged();
        pull.Controls.Add(_pullerEngageRange);
        pull.Controls.Add(new Label { Text = "yalms", AutoSize = true, Padding = new Padding(0, 4, 0, 0) });
		_campSet = new Button { Text = "Set camp here", AutoSize = true };
		_campSet.Click += (_, _) => OnCampSet();
		pull.Controls.Add(_campSet);
		_campClear = new Button { Text = "Clear camp", AutoSize = true };
		_campClear.Click += (_, _) => OnCampClear();
		pull.Controls.Add(_campClear);
		_campStatus = new Label { Text = "Camp not set", AutoSize = true, Padding = new Padding(8, 4, 0, 0) };
		pull.Controls.Add(_campStatus);
        leftCol.Controls.Add(new Label { Text = "puller", AutoSize = true }, 0, lr);
        leftCol.Controls.Add(pull, 1, lr);
        lr++;

        var rightCol = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Fill,
            ColumnCount = 2,
            Padding = new Padding(8, 0, 0, 0),
        };
        rightCol.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 150));
        rightCol.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        var dr = 0;
        rightCol.Controls.Add(new Label { Text = "defensive_provider", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);
        _defProviderCombo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(100, 0),
        };
        _defProviderCombo.Items.AddRange(new object[] { "internal", "healbot" });
        _defProviderCombo.SelectedIndexChanged += (_, _) => OnDefProviderSelected();
        rightCol.Controls.Add(_defProviderCombo, 1, dr);
        dr++;
        rightCol.Controls.Add(new Label { Text = "def_critical_hpp", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);
        _defCrit = new TextBox { Width = 72, Anchor = AnchorStyles.Left };
        _defCrit.Leave += (_, _) => OnDefThresholdChanged();
        rightCol.Controls.Add(_defCrit, 1, dr);
        dr++;
        rightCol.Controls.Add(new Label { Text = "def_medium_hpp", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);
        _defMed = new TextBox { Width = 72, Anchor = AnchorStyles.Left };
        _defMed.Leave += (_, _) => OnDefThresholdChanged();
        rightCol.Controls.Add(_defMed, 1, dr);
        dr++;
        rightCol.Controls.Add(new Label { Text = "heal_min_tier", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);
        _defHealMinTier = new TextBox { Width = 72, Anchor = AnchorStyles.Left };
        _defHealMinTier.Leave += (_, _) => OnDefThresholdChanged();
        rightCol.Controls.Add(_defHealMinTier, 1, dr);
        dr++;
        rightCol.Controls.Add(new Label { Text = "heal_max_tier", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);
        _defHealMaxTier = new TextBox { Width = 72, Anchor = AnchorStyles.Left };
        _defHealMaxTier.Leave += (_, _) => OnDefThresholdChanged();
        rightCol.Controls.Add(_defHealMaxTier, 1, dr);
        dr++;
        rightCol.Controls.Add(new Label { Text = "heal_min_missing_hp", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);
        _defHealMinMissingHp = new TextBox { Width = 72, Anchor = AnchorStyles.Left };
        _defHealMinMissingHp.Leave += (_, _) => OnDefThresholdChanged();
        rightCol.Controls.Add(_defHealMinMissingHp, 1, dr);
        dr++;
        rightCol.Controls.Add(new Label { Text = "heal_ignore_trusts", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);
        _defHealIgnoreTrusts = new CheckBox { AutoSize = true, Anchor = AnchorStyles.Left };
        _defHealIgnoreTrusts.CheckedChanged += (_, _) => OnDefThresholdChanged();
        rightCol.Controls.Add(_defHealIgnoreTrusts, 1, dr);
        dr++;
        rightCol.Controls.Add(new Label { Text = "buff_overwrite_s", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);
        _defOverwrite = new TextBox { Width = 72, Anchor = AnchorStyles.Left };
        _defOverwrite.Leave += (_, _) => OnDefThresholdChanged();
        rightCol.Controls.Add(_defOverwrite, 1, dr);
        dr++;
        rightCol.Controls.Add(new Label { Text = "defensive_buffs (|)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);
        _defBuffs = new TextBox { Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top, MinimumSize = new Size(80, 23) };
        _defBuffs.Leave += (_, _) => OnDefThresholdChanged();
        rightCol.Controls.Add(_defBuffs, 1, dr);
        dr++;
        rightCol.Controls.Add(new Label { Text = "targeted_buffs (Target:Buff|...)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, dr);
        _defTargetedBuffs = new TextBox { Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top, MinimumSize = new Size(80, 23) };
        _defTargetedBuffs.Leave += (_, _) => OnDefThresholdChanged();
        rightCol.Controls.Add(_defTargetedBuffs, 1, dr);
        dr++;

        topSplit.Controls.Add(leftCol, 0, 0);
        topSplit.Controls.Add(rightCol, 1, 0);
        g.Controls.Add(topSplit, 0, gRow++);

        _grpFightLeader = new GroupBox
        {
            Text = "Fight leader — autotarget stays on the leader target unless an eligible fight-add is valid.",
            Dock = DockStyle.Top,
            Padding = new Padding(8),
            AutoSize = true,
        };
        var flTop = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        var flCb = MkGlobal("fight_leader");
        flTop.Controls.Add(flCb);
        _fightLeaderCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
        _fightLeaderCombo.SelectedIndexChanged += (_, _) => OnFightLeaderSelected();
        flTop.Controls.Add(_fightLeaderCombo);
        var flFlow = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Fill, WrapContents = false, Padding = new Padding(0) };
        flFlow.Controls.Add(flTop);
        var pfTop = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(0, 6, 0, 0) };
        pfTop.Controls.Add(MkGlobal("party_follow"));
        _partyFollowCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 200 };
        _partyFollowCombo.SelectedIndexChanged += (_, _) => OnPartyFollowSelected();
        pfTop.Controls.Add(_partyFollowCombo);
        pfTop.Controls.Add(new Label { Text = "Min yalms", AutoSize = true, Padding = new Padding(10, 4, 0, 0) });
        _pfFollowMinYalms = new TextBox { Width = 52 };
        _pfFollowMinYalms.Leave += (_, _) => OnPartyFollowDistanceChanged();
        pfTop.Controls.Add(_pfFollowMinYalms);
        pfTop.Controls.Add(new Label { Text = "Max yalms", AutoSize = true, Padding = new Padding(8, 4, 0, 0) });
        _pfFollowMaxYalms = new TextBox { Width = 52 };
        _pfFollowMaxYalms.Leave += (_, _) => OnPartyFollowDistanceChanged();
        pfTop.Controls.Add(_pfFollowMaxYalms);
        pfTop.Controls.Add(new Label { Text = "Fight min", AutoSize = true, Padding = new Padding(8, 4, 0, 0) });
        _pfFightFollowMinYalms = new TextBox { Width = 52 };
        _pfFightFollowMinYalms.Leave += (_, _) => OnPartyFollowDistanceChanged();
        pfTop.Controls.Add(_pfFightFollowMinYalms);
        pfTop.Controls.Add(new Label { Text = "Hold s", AutoSize = true, Padding = new Padding(8, 4, 0, 0) });
        _pfFightFollowHoldS = new TextBox { Width = 52 };
        _pfFightFollowHoldS.Leave += (_, _) => OnPartyFollowDistanceChanged();
        pfTop.Controls.Add(_pfFightFollowHoldS);
        flFlow.Controls.Add(pfTop);
        _partyFollowModeWarning = new Label
        {
            AutoSize = true,
            ForeColor = Color.DarkOrange,
            Visible = false,
            Text = "Non-UC follow target selected; precision may be lower.",
            Padding = new Padding(2, 2, 0, 0),
        };
        flFlow.Controls.Add(_partyFollowModeWarning);
        _grpFightLeader.Controls.Add(flFlow);
        g.Controls.Add(_grpFightLeader, 0, gRow++);

		var nyzulGroup = new GroupBox
		{
			Text = "Nyzul lamp parking — coordinator profile owns the ordered runtime queue.",
			Dock = DockStyle.Top,
			Padding = new Padding(8),
			AutoSize = true,
		};
		var nyzulFlow = new FlowLayoutPanel
		{
			FlowDirection = FlowDirection.TopDown,
			AutoSize = true,
			Dock = DockStyle.Fill,
			WrapContents = false,
		};
		var nyzulNames = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
		nyzulNames.Controls.Add(new Label { Text = "Coordinator", AutoSize = true, Padding = new Padding(0, 4, 0, 0) });
		_nyzulCoordinatorCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 180 };
		_nyzulCoordinatorCombo.SelectedIndexChanged += (_, _) => OnNyzulConfigChanged();
		nyzulNames.Controls.Add(_nyzulCoordinatorCombo);
		nyzulNames.Controls.Add(new Label { Text = "Anchor", AutoSize = true, Padding = new Padding(10, 4, 0, 0) });
		_nyzulAnchorCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 180 };
		_nyzulAnchorCombo.SelectedIndexChanged += (_, _) => OnNyzulConfigChanged();
		nyzulNames.Controls.Add(_nyzulAnchorCombo);
		nyzulFlow.Controls.Add(nyzulNames);
		_nyzulParkingList = new ListBox
		{
			Height = 82,
			IntegralHeight = false,
			Width = 380,
			Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
		};
		nyzulFlow.Controls.Add(_nyzulParkingList);
		var nyzulButtons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
		nyzulButtons.Controls.Add(new Label { Text = "Next parker", AutoSize = true, Padding = new Padding(0, 4, 0, 0) });
		_nyzulParkerCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 180 };
		nyzulButtons.Controls.Add(_nyzulParkerCombo);
		_nyzulParkerAdd = new Button { Text = "Add", AutoSize = true };
		_nyzulParkerAdd.Click += (_, _) => NyzulParkerAdd();
		nyzulButtons.Controls.Add(_nyzulParkerAdd);
		_nyzulParkerRemove = new Button { Text = "Remove", AutoSize = true };
		_nyzulParkerRemove.Click += (_, _) => NyzulParkerRemove();
		nyzulButtons.Controls.Add(_nyzulParkerRemove);
		_nyzulParkerUp = new Button { Text = "Up", AutoSize = true };
		_nyzulParkerUp.Click += (_, _) => NyzulParkerMove(-1);
		nyzulButtons.Controls.Add(_nyzulParkerUp);
		_nyzulParkerDown = new Button { Text = "Down", AutoSize = true };
		_nyzulParkerDown.Click += (_, _) => NyzulParkerMove(1);
		nyzulButtons.Controls.Add(_nyzulParkerDown);
		nyzulFlow.Controls.Add(nyzulButtons);
		nyzulGroup.Controls.Add(nyzulFlow);
		g.Controls.Add(nyzulGroup, 0, gRow++);

        var listsSplit = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 2,
            Padding = new Padding(0, 6, 0, 0),
        };
        listsSplit.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50f));
        listsSplit.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 50f));
        listsSplit.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        listsSplit.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        listsSplit.RowStyles.Add(new RowStyle(SizeType.AutoSize));

        _grpAddPri = new GroupBox
        {
            Text = "Fight-add priority — only listed mobs are eligible; Up/Down reorders.",
            Dock = DockStyle.Fill,
            Padding = new Padding(8),
            AutoSize = true,
            MinimumSize = new Size(200, 120),
        };
        var apFlow = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Fill, WrapContents = false };
        _addPriList = new ListBox { Height = 90, IntegralHeight = false, Dock = DockStyle.Top, Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top };
        apFlow.Controls.Add(_addPriList);
        var apr = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(0, 6, 0, 0) };
        apr.Controls.Add(new Label { Text = "Mob name:", AutoSize = true });
        _addPriName = new TextBox { Width = 220 };
        apr.Controls.Add(_addPriName);
        _addPriByName = new Button { Text = "Add by name", AutoSize = true };
        _addPriByName.Click += (_, _) => AddPriorityByName();
        apr.Controls.Add(_addPriByName);
        _addPriCurTarget = new Button { Text = "Add current target", AutoSize = true };
        _addPriCurTarget.Click += (_, _) => AddPriorityCurrent();
        apr.Controls.Add(_addPriCurTarget);
        _addPriRemove = new Button { Text = "Remove selected", AutoSize = true };
        _addPriRemove.Click += (_, _) => AddPriorityRemove();
        apr.Controls.Add(_addPriRemove);
        _addPriUp = new Button { Text = "Move up", AutoSize = true };
        _addPriUp.Click += (_, _) => AddPriorityMove("up");
        apr.Controls.Add(_addPriUp);
        _addPriDown = new Button { Text = "Move down", AutoSize = true };
        _addPriDown.Click += (_, _) => AddPriorityMove("down");
        apr.Controls.Add(_addPriDown);
        apFlow.Controls.Add(apr);
        _grpAddPri.Controls.Add(apFlow);
        listsSplit.Controls.Add(_grpAddPri, 0, 0);

        _grpPartner = new GroupBox
        {
            Text = "Partner follow — skip autotarget for these party members' targets.",
            Dock = DockStyle.Fill,
            Padding = new Padding(8),
            AutoSize = true,
            MinimumSize = new Size(200, 120),
        };
        var pFlow = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Fill, WrapContents = false };
        var pen = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        pen.Controls.Add(MkGlobal("partner"));
        pFlow.Controls.Add(pen);
        _partnerList = new ListBox { Height = 80, IntegralHeight = false, Dock = DockStyle.Top, Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top };
        pFlow.Controls.Add(_partnerList);
        var pr = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(0, 6, 0, 0) };
        pr.Controls.Add(new Label { Text = "Name:", AutoSize = true });
        _partnerName = new TextBox { Width = 220 };
        pr.Controls.Add(_partnerName);
        _partnerByName = new Button { Text = "Add by name", AutoSize = true };
        _partnerByName.Click += (_, _) => PartnerAddByName();
        pr.Controls.Add(_partnerByName);
        _partnerCurTarget = new Button { Text = "Add current target", AutoSize = true };
        _partnerCurTarget.Click += (_, _) => PartnerAddCurrent();
        pr.Controls.Add(_partnerCurTarget);
        _partnerRemove = new Button { Text = "Remove selected", AutoSize = true };
        _partnerRemove.Click += (_, _) => PartnerRemove();
        pr.Controls.Add(_partnerRemove);
        pFlow.Controls.Add(pr);
        _grpPartner.Controls.Add(pFlow);
        listsSplit.Controls.Add(_grpPartner, 0, 1);

        _grpIgnore = new GroupBox
        {
            Text = "WS wait ignore — party members skipped for WS-hold decisions.",
            Dock = DockStyle.Fill,
            Padding = new Padding(8),
            AutoSize = true,
            MinimumSize = new Size(200, 120),
        };
        var iFlow = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Fill, WrapContents = false };
        _ignoreList = new ListBox { Height = 80, IntegralHeight = false, Dock = DockStyle.Top, Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top };
        iFlow.Controls.Add(_ignoreList);
        var ign = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(0, 6, 0, 0) };
        ign.Controls.Add(new Label { Text = "Mob name:", AutoSize = true });
        _ignoreName = new TextBox { Width = 220 };
        ign.Controls.Add(_ignoreName);
        _ignoreByName = new Button { Text = "Add by name", AutoSize = true };
        _ignoreByName.Click += (_, _) => IgnoreAddByName();
        ign.Controls.Add(_ignoreByName);
        _ignoreCurTarget = new Button { Text = "Add current target", AutoSize = true };
        _ignoreCurTarget.Click += (_, _) => IgnoreAddCurrent();
        ign.Controls.Add(_ignoreCurTarget);
        _ignoreRemove = new Button { Text = "Remove selected", AutoSize = true };
        _ignoreRemove.Click += (_, _) => IgnoreRemove();
        ign.Controls.Add(_ignoreRemove);
        iFlow.Controls.Add(ign);
        _grpIgnore.Controls.Add(iFlow);
        listsSplit.Controls.Add(_grpIgnore, 1, 0);

        _grpTargetIgn = new GroupBox
        {
            Text = "Target ignore (autotarget) — mobs never chosen as combat targets.",
            Dock = DockStyle.Fill,
            Padding = new Padding(8),
            AutoSize = true,
            MinimumSize = new Size(200, 120),
        };
        var tiFlow = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Fill, WrapContents = false };
        _targetIgnList = new ListBox { Height = 80, IntegralHeight = false, Dock = DockStyle.Top, Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top };
        tiFlow.Controls.Add(_targetIgnList);
        var tigr = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(0, 6, 0, 0) };
        tigr.Controls.Add(new Label { Text = "Mob name:", AutoSize = true });
        _targetIgnName = new TextBox { Width = 220 };
        tigr.Controls.Add(_targetIgnName);
        _targetIgnByName = new Button { Text = "Add by name", AutoSize = true };
        _targetIgnByName.Click += (_, _) => TargetIgnAddByName();
        tigr.Controls.Add(_targetIgnByName);
        _targetIgnCurTarget = new Button { Text = "Add current target", AutoSize = true };
        _targetIgnCurTarget.Click += (_, _) => TargetIgnAddCurrent();
        tigr.Controls.Add(_targetIgnCurTarget);
        _targetIgnRemove = new Button { Text = "Remove selected", AutoSize = true };
        _targetIgnRemove.Click += (_, _) => TargetIgnRemove();
        tigr.Controls.Add(_targetIgnRemove);
        tiFlow.Controls.Add(tigr);
        _grpTargetIgn.Controls.Add(tiFlow);
        listsSplit.Controls.Add(_grpTargetIgn, 1, 1);

        _grpSleepSpells = new GroupBox
        {
            Text = "Sleep spells — ordered list used for pre-engage and in-combat Sleep picks.",
            Dock = DockStyle.Fill,
            Padding = new Padding(8),
            AutoSize = true,
            MinimumSize = new Size(200, 120),
        };
        var sleepFlow = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Fill, WrapContents = false };
        var sleepRangeRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        sleepRangeRow.Controls.Add(new Label { Text = "Eligible mob range", AutoSize = true, Padding = new Padding(0, 4, 0, 0) });
        _sleepMaxTargetRange = new TextBox { Width = 52 };
        _sleepMaxTargetRange.Leave += (_, _) => OnSleepMaxTargetRangeChanged();
        sleepRangeRow.Controls.Add(_sleepMaxTargetRange);
        sleepRangeRow.Controls.Add(new Label { Text = "yalms", AutoSize = true, Padding = new Padding(0, 4, 0, 0) });
        sleepFlow.Controls.Add(sleepRangeRow);
        _sleepSpellList = new ListBox { Height = 90, IntegralHeight = false, Dock = DockStyle.Top, Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top };
        sleepFlow.Controls.Add(_sleepSpellList);
        var sleepRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(0, 6, 0, 0), WrapContents = false };
        sleepRow.Controls.Add(new Label { Text = "Spell name:", AutoSize = true });
        _sleepSpellName = new TextBox { Width = 220 };
        sleepRow.Controls.Add(_sleepSpellName);
        _sleepSpellSetOnly = new Button { Text = "Set only", AutoSize = true };
        _sleepSpellSetOnly.Click += (_, _) => SleepSpellSetOnly();
        sleepRow.Controls.Add(_sleepSpellSetOnly);
        _sleepSpellAdd = new Button { Text = "Add", AutoSize = true };
        _sleepSpellAdd.Click += (_, _) => SleepSpellAddByName();
        sleepRow.Controls.Add(_sleepSpellAdd);
        _sleepSpellRemove = new Button { Text = "Remove selected", AutoSize = true };
        _sleepSpellRemove.Click += (_, _) => SleepSpellRemove();
        sleepRow.Controls.Add(_sleepSpellRemove);
        _sleepSpellClear = new Button { Text = "Clear list", AutoSize = true };
        _sleepSpellClear.Click += (_, _) => SleepSpellClear();
        sleepRow.Controls.Add(_sleepSpellClear);
        _sleepSpellUp = new Button { Text = "Move up", AutoSize = true };
        _sleepSpellUp.Click += (_, _) => SleepSpellMove("up");
        sleepRow.Controls.Add(_sleepSpellUp);
        _sleepSpellDown = new Button { Text = "Move down", AutoSize = true };
        _sleepSpellDown.Click += (_, _) => SleepSpellMove("down");
        sleepRow.Controls.Add(_sleepSpellDown);
        sleepFlow.Controls.Add(sleepRow);
        _grpSleepSpells.Controls.Add(sleepFlow);
        listsSplit.Controls.Add(_grpSleepSpells, 0, 2);
        listsSplit.SetColumnSpan(_grpSleepSpells, 2);

        g.Controls.Add(listsSplit, 0, gRow++);

        var tankGroup = new GroupBox
        {
            Text = "Tank Enmity Actions — single prioritized JA/spell list for threat recovery.",
            Dock = DockStyle.Top,
            Padding = new Padding(8),
            AutoSize = true,
            MinimumSize = new Size(200, 120),
        };
        var tankFlow = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true, Dock = DockStyle.Fill, WrapContents = false };
        _tankEnmityList = new ListBox
        {
            Height = 90,
            IntegralHeight = false,
            Dock = DockStyle.Top,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
        };
        tankFlow.Controls.Add(_tankEnmityList);
        var tankAddRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, Padding = new Padding(0, 6, 0, 0) };
        _tankEnmityTypeCombo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 70,
        };
        _tankEnmityTypeCombo.Items.Add("ja");
        _tankEnmityTypeCombo.Items.Add("spell");
        _tankEnmityTypeCombo.SelectedItem = "ja";
        _tankEnmityTypeCombo.SelectedIndexChanged += (_, _) => OnTankEnmityTypeChanged();
        tankAddRow.Controls.Add(_tankEnmityTypeCombo);
        _tankEnmityNameCombo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDown,
            Width = 260,
        };
        _tankEnmityNameCombo.DropDown += (_, _) =>
        {
            var sid = _selectedSid;
            if (!string.IsNullOrWhiteSpace(sid))
            {
                EnsureOptionsHydrated(sid);
            }
        };
        tankAddRow.Controls.Add(_tankEnmityNameCombo);
        _tankEnmityAdd = new Button { Text = "Add", AutoSize = true };
        _tankEnmityAdd.Click += (_, _) => OnTankEnmityAdd();
        tankAddRow.Controls.Add(_tankEnmityAdd);
        tankFlow.Controls.Add(tankAddRow);
        var tankBtnRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        _tankEnmityRemove = new Button { Text = "Remove", AutoSize = true };
        _tankEnmityRemove.Click += (_, _) => OnTankEnmityRemove();
        _tankEnmityUp = new Button { Text = "Up", AutoSize = true };
        _tankEnmityUp.Click += (_, _) => OnTankEnmityMove("up");
        _tankEnmityDown = new Button { Text = "Down", AutoSize = true };
        _tankEnmityDown.Click += (_, _) => OnTankEnmityMove("down");
        tankBtnRow.Controls.Add(_tankEnmityRemove);
        tankBtnRow.Controls.Add(_tankEnmityUp);
        tankBtnRow.Controls.Add(_tankEnmityDown);
        tankFlow.Controls.Add(tankBtnRow);
        tankGroup.Controls.Add(tankFlow);
        g.Controls.Add(tankGroup, 0, gRow++);

        _settingsTabs = new TabControl
        {
            Dock = DockStyle.Top,
            Height = 520,
        };
        var tabGeneral = new TabPage("General");
        tabGeneral.AutoScroll = true;
        g.Dock = DockStyle.Top;
        tabGeneral.Controls.Add(g);
        _settingsTabs.TabPages.Add(tabGeneral);

        var tabSpacing = new TabPage("Spacing Tuning");
        tabSpacing.AutoScroll = true;
        var sp = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 2,
            Padding = new Padding(8),
        };
        sp.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 220));
        sp.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        var sr = 0;
        sp.Controls.Add(new Label { Text = "Use target prediction", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spUsePrediction = new CheckBox { AutoSize = true, Anchor = AnchorStyles.Left };
        _spUsePrediction.CheckedChanged += (_, _) => OnSpacingTuningBoolChanged();
        sp.Controls.Add(_spUsePrediction, 1, sr++);
        sp.Controls.Add(new Label { Text = "Combat band min (real)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spBandMin = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spBandMin.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spBandMin, 1, sr++);
        sp.Controls.Add(new Label { Text = "Combat band max (real)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spBandMax = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spBandMax.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spBandMax, 1, sr++);
        sp.Controls.Add(new Label { Text = "Model size floor (movement)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spModelSizeFloor = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spModelSizeFloor.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spModelSizeFloor, 1, sr++);
        sp.Controls.Add(new Label { Text = "Prediction lookahead (s)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spLookahead = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spLookahead.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spLookahead, 1, sr++);
        sp.Controls.Add(new Label { Text = "Repel hold ticks", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spAnchorInvalidTicks = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spAnchorInvalidTicks.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spAnchorInvalidTicks, 1, sr++);
        sp.Controls.Add(new Label { Text = "Overlap deadband", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spEmergencyMargin = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spEmergencyMargin.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spEmergencyMargin, 1, sr++);
        sp.Controls.Add(new Label { Text = "Repel weight", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spSwitchMargin = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spSwitchMargin.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spSwitchMargin, 1, sr++);
        sp.Controls.Add(new Label { Text = "Band deadband", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spArrivalTolerance = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spArrivalTolerance.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spArrivalTolerance, 1, sr++);
        tabSpacing.Controls.Add(sp);
        _settingsTabs.TabPages.Add(tabSpacing);

        var tabFormation = new TabPage("Encounter Formation") { AutoScroll = true };
        var formationRoot = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 1,
            Padding = new Padding(8),
        };
        _formationEnabled = new CheckBox { Text = "Enable encounter formation", AutoSize = true };
        _formationEnabled.CheckedChanged += (_, _) => OnFormationConfigChanged();
        formationRoot.Controls.Add(_formationEnabled);
        formationRoot.Controls.Add(new Label
        {
            Text = "Profile-scoped positioning for supported encounters. Settings are saved to Profile V2 and are not sent over the live mirror.",
            AutoSize = true,
            MaximumSize = new Size(760, 0),
            Padding = new Padding(0, 4, 0, 8),
        });

        var formationOwnership = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
        };
        _formationValidation = new Label { AutoSize = true, Padding = new Padding(0, 6, 10, 0) };
        _formationEnableOwnership = new Button { Text = "Enable required movement domain", AutoSize = true };
        _formationEnableOwnership.Click += (_, _) => OnFormationEnableOwnership();
        formationOwnership.Controls.Add(_formationValidation);
        formationOwnership.Controls.Add(_formationEnableOwnership);
        formationRoot.Controls.Add(formationOwnership);

        _formationConfigPanel = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 2,
            Padding = new Padding(0, 8, 0, 0),
        };
        _formationConfigPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 260));
        _formationConfigPanel.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 250));
        var formationRow = 0;

        _formationConfigPanel.Controls.Add(new Label { Text = "Encounter", AutoSize = true, Anchor = AnchorStyles.Left }, 0, formationRow);
        _formationEncounter = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 230 };
        _formationEncounter.Items.Add("Lady Lilith — Easy");
        _formationEncounter.SelectedIndex = 0;
        _formationEncounter.SelectedIndexChanged += (_, _) => OnFormationConfigChanged();
        _formationConfigPanel.Controls.Add(_formationEncounter, 1, formationRow++);

        _formationConfigPanel.Controls.Add(new Label { Text = "Character role", AutoSize = true, Anchor = AnchorStyles.Left }, 0, formationRow);
        _formationRole = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 160 };
        _formationRole.Items.AddRange(["Disabled", "Tank", "DPS", "Healer"]);
        _formationRole.SelectedItem = "Disabled";
        _formationRole.SelectedIndexChanged += (_, _) => OnFormationConfigChanged();
        _formationConfigPanel.Controls.Add(_formationRole, 1, formationRow++);

        _formationConfigPanel.Controls.Add(new Label { Text = "Tank character", AutoSize = true, Anchor = AnchorStyles.Left }, 0, formationRow);
        _formationTankName = new ComboBox { DropDownStyle = ComboBoxStyle.DropDown, Width = 230 };
        _formationTankName.SelectedIndexChanged += (_, _) => OnFormationConfigChanged();
        _formationTankName.Leave += (_, _) => OnFormationConfigChanged();
        _formationConfigPanel.Controls.Add(_formationTankName, 1, formationRow++);

        _formationConfigPanel.Controls.Add(new Label
        {
            Text = "Healer coverage members",
            AutoSize = true,
            Anchor = AnchorStyles.Left | AnchorStyles.Top,
            Padding = new Padding(0, 5, 0, 0),
        }, 0, formationRow);
        _formationRequiredParty = new CheckedListBox
        {
            CheckOnClick = true,
            Height = 92,
            Width = 230,
            IntegralHeight = false,
        };
        _formationRequiredParty.ItemCheck += (_, _) => OnFormationRequiredPartyItemCheck();
        _formationConfigPanel.Controls.Add(_formationRequiredParty, 1, formationRow++);

        AddFormationSectionLabel(_formationConfigPanel, "Arena capture", ref formationRow);
        _formationCaptureStable = CreateFormationNumber(0.10m, 5.00m, 0.50m, 0.05m, 2);
        AddFormationNumberRow(_formationConfigPanel, "Stable observation (seconds)", _formationCaptureStable, ref formationRow);
        _formationCaptureTolerance = CreateFormationNumber(0.01m, 1.00m, 0.10m, 0.01m, 2);
        AddFormationNumberRow(_formationConfigPanel, "Position tolerance (yalms)", _formationCaptureTolerance, ref formationRow);
        _formationSafeRadius = CreateFormationNumber(5.0m, 30.0m, 16.0m, 0.5m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Arena safe radius (yalms)", _formationSafeRadius, ref formationRow);

        AddFormationSectionLabel(_formationConfigPanel, "Tank center tether", ref formationRow);
        _formationTankAcceptRadius = CreateFormationNumber(0.1m, 10.0m, 1.5m, 0.1m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Centered inside (yalms)", _formationTankAcceptRadius, ref formationRow);
        _formationTankReturnRadius = CreateFormationNumber(0.2m, 15.0m, 3.0m, 0.1m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Return outside (yalms)", _formationTankReturnRadius, ref formationRow);

        AddFormationSectionLabel(_formationConfigPanel, "DPS flank", ref formationRow);
        _formationDpsFlankAngle = CreateFormationNumber(1.0m, 179.0m, 90.0m, 1.0m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Right-flank angle (degrees)", _formationDpsFlankAngle, ref formationRow);
        _formationDpsMeleeRadius = CreateFormationNumber(0.5m, 8.0m, 3.0m, 0.1m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Melee radius (yalms)", _formationDpsMeleeRadius, ref formationRow);
        _formationDpsPositionTolerance = CreateFormationNumber(0.1m, 5.0m, 1.5m, 0.1m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Position tolerance (yalms)", _formationDpsPositionTolerance, ref formationRow);

        AddFormationSectionLabel(_formationConfigPanel, "Healer constraints", ref formationRow);
        _formationHealerPreferredRadius = CreateFormationNumber(2.0m, 25.0m, 12.0m, 0.5m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Preferred center radius (yalms)", _formationHealerPreferredRadius, ref formationRow);
        _formationHealerMinimumBossDistance = CreateFormationNumber(1.0m, 20.0m, 8.0m, 0.5m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Minimum boss distance (yalms)", _formationHealerMinimumBossDistance, ref formationRow);
        _formationHealerMaximumPartyRange = CreateFormationNumber(2.0m, 25.0m, 18.0m, 0.5m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Maximum party range (yalms)", _formationHealerMaximumPartyRange, ref formationRow);
        _formationHealerConeHalfAngle = CreateFormationNumber(1.0m, 89.0m, 50.0m, 1.0m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Threat cone half-angle (degrees)", _formationHealerConeHalfAngle, ref formationRow);
        _formationHealerConeSafetyMargin = CreateFormationNumber(1.0m, 45.0m, 15.0m, 1.0m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Cone safety margin (degrees)", _formationHealerConeSafetyMargin, ref formationRow);
        _formationHealerSampleStep = CreateFormationNumber(1.0m, 45.0m, 10.0m, 1.0m, 1);
        AddFormationNumberRow(_formationConfigPanel, "Search sample step (degrees)", _formationHealerSampleStep, ref formationRow);

        foreach (var numeric in FormationNumericControls())
        {
            numeric.ValueChanged += (_, _) => OnFormationConfigChanged();
        }
        formationRoot.Controls.Add(_formationConfigPanel);
        tabFormation.Controls.Add(formationRoot);
        _settingsTabs.TabPages.Add(tabFormation);

        var tabPathing = new TabPage("Pathing");
        tabPathing.AutoScroll = true;
        var path = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 2,
            Padding = new Padding(8),
        };
        path.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 180));
        path.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        var pathRow = 0;
        var rec = MkGlobal("path_recording");
        var fol = MkGlobal("path_follow_enabled");
        path.Controls.Add(rec, 0, pathRow);
        path.SetColumnSpan(rec, 2);
        pathRow++;
        path.Controls.Add(fol, 0, pathRow);
        path.SetColumnSpan(fol, 2);
        pathRow++;
        path.Controls.Add(new Label { Text = "Path file", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathFileValue = new Label { Text = "", AutoSize = true, Anchor = AnchorStyles.Left };
        path.Controls.Add(_pathFileValue, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Route type", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathRouteTypeValue = new Label { Text = "unknown", AutoSize = true, Anchor = AnchorStyles.Left };
        path.Controls.Add(_pathRouteTypeValue, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Distance to start", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathDistanceValue = new Label { Text = "0.0", AutoSize = true, Anchor = AnchorStyles.Left };
        path.Controls.Add(_pathDistanceValue, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Recorded points", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathPointCountValue = new Label { Text = "0", AutoSize = true, Anchor = AnchorStyles.Left };
        path.Controls.Add(_pathPointCountValue, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Party gate (yalms)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathPartyGateYalms = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _pathPartyGateYalms.Leave += (_, _) => OnPathPartyGateChanged();
        path.Controls.Add(_pathPartyGateYalms, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Resume index window", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathResumeIndexWindow = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _pathResumeIndexWindow.Leave += (_, _) => OnPathResumeIndexWindowChanged();
        path.Controls.Add(_pathResumeIndexWindow, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Hunter max Z delta", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathHunterMaxZDelta = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _pathHunterMaxZDelta.Leave += (_, _) => OnPathHunterMaxZDeltaChanged();
        path.Controls.Add(_pathHunterMaxZDelta, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Hunter max range (yalms)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathHunterMaxTargetRange = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _pathHunterMaxTargetRange.Leave += (_, _) => OnPathHunterMaxTargetRangeChanged();
        path.Controls.Add(_pathHunterMaxTargetRange, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Hunter claim timeout (s)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathHunterClaimTimeout = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _pathHunterClaimTimeout.Leave += (_, _) => OnPathHunterClaimTimeoutChanged();
        path.Controls.Add(_pathHunterClaimTimeout, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Hunter ignore cooldown (s)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathHunterIgnoreCooldown = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _pathHunterIgnoreCooldown.Leave += (_, _) => OnPathHunterIgnoreCooldownChanged();
        path.Controls.Add(_pathHunterIgnoreCooldown, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Pull action type", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathPullActionType = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(120, 0),
        };
        _pathPullActionType.Items.Add("ja");
        _pathPullActionType.Items.Add("spell");
        _pathPullActionType.DropDown += (_, _) =>
        {
            var sid = _selectedSid;
            if (!string.IsNullOrWhiteSpace(sid))
            {
                EnsureOptionsHydrated(sid);
            }
        };
        _pathPullActionType.SelectedIndexChanged += (_, _) => OnPathPullActionTypeChanged();
        path.Controls.Add(_pathPullActionType, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Pull action", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        _pathPullActionName = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDown,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(220, 0),
        };
        _pathPullActionName.DropDown += (_, _) =>
        {
            var sid = _selectedSid;
            if (!string.IsNullOrWhiteSpace(sid))
            {
                EnsureOptionsHydrated(sid);
            }
        };
        _pathPullActionName.SelectedIndexChanged += (_, _) => OnPathPullActionNameChanged();
        path.Controls.Add(_pathPullActionName, 1, pathRow++);
        path.Controls.Add(new Label { Text = "Path hunter targets", AutoSize = true, Anchor = AnchorStyles.Left }, 0, pathRow);
        pathRow++;
        _pathHunterList = new ListBox
        {
            Height = 100,
            IntegralHeight = false,
            Dock = DockStyle.Top,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
        };
        path.Controls.Add(_pathHunterList, 0, pathRow);
        path.SetColumnSpan(_pathHunterList, 2);
        pathRow++;
        var pathHunterRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        _pathHunterName = new TextBox { Width = 220 };
        _pathHunterAdd = new Button { Text = "Add by name", AutoSize = true };
        _pathHunterAdd.Click += (_, _) => OnPathHunterAdd();
        _pathHunterRemove = new Button { Text = "Remove selected", AutoSize = true };
        _pathHunterRemove.Click += (_, _) => OnPathHunterRemove();
        pathHunterRow.Controls.Add(_pathHunterName);
        pathHunterRow.Controls.Add(_pathHunterAdd);
        pathHunterRow.Controls.Add(_pathHunterRemove);
        path.Controls.Add(pathHunterRow, 0, pathRow);
        path.SetColumnSpan(pathHunterRow, 2);
        pathRow++;
        tabPathing.Controls.Add(path);
        _settingsTabs.TabPages.Add(tabPathing);

        AddGeoPullTabs();

        _tabSummoner = new TabPage("SMN") { AutoScroll = true };
        var summonerRoot = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 2,
            Padding = new Padding(8),
        };
        summonerRoot.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 190));
        summonerRoot.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        var summonerRow = 0;
        _summonerEnabled = new CheckBox { Text = "Enable Summoner automation", AutoSize = true };
        _summonerEnabled.CheckedChanged += (_, _) => OnSummonerSettingChanged();
        summonerRoot.Controls.Add(_summonerEnabled, 0, summonerRow);
        summonerRoot.SetColumnSpan(_summonerEnabled, 2);
        summonerRow++;
        summonerRoot.Controls.Add(
            new Label { Text = "Desired avatar", AutoSize = true, Anchor = AnchorStyles.Left },
            0,
            summonerRow
        );
        _summonerAvatar = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 260,
            Anchor = AnchorStyles.Left,
        };
        _summonerAvatar.Items.Add("");
        foreach (var avatar in SummonerCapabilities.Avatars)
        {
            _summonerAvatar.Items.Add(avatar.Name);
        }
        _summonerAvatar.SelectedIndex = 0;
        _summonerAvatar.SelectedIndexChanged += (_, _) => OnSummonerAvatarChanged();
        summonerRoot.Controls.Add(_summonerAvatar, 1, summonerRow++);
        _summonerAvatarFavor = new CheckBox { Text = "Maintain Avatar's Favor", AutoSize = true };
        _summonerAvatarFavor.CheckedChanged += (_, _) => OnSummonerSettingChanged();
        summonerRoot.Controls.Add(_summonerAvatarFavor, 0, summonerRow);
        summonerRoot.SetColumnSpan(_summonerAvatarFavor, 2);
        summonerRow++;
        _summonerWardEnabled = new CheckBox { Text = "Maintain one Blood Pact: Ward effect", AutoSize = true };
        _summonerWardEnabled.CheckedChanged += (_, _) => OnSummonerSettingChanged();
        summonerRoot.Controls.Add(_summonerWardEnabled, 0, summonerRow);
        summonerRoot.SetColumnSpan(_summonerWardEnabled, 2);
        summonerRow++;
        summonerRoot.Controls.Add(
            new Label { Text = "Ward action", AutoSize = true, Anchor = AnchorStyles.Left },
            0,
            summonerRow
        );
        _summonerWardAction = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 260,
            Anchor = AnchorStyles.Left,
        };
        _summonerWardAction.SelectedIndexChanged += (_, _) => OnSummonerActionChanged();
        summonerRoot.Controls.Add(_summonerWardAction, 1, summonerRow++);
        _summonerEngage = new CheckBox { Text = "Engage the combat target with Assault", AutoSize = true };
        _summonerEngage.CheckedChanged += (_, _) => OnSummonerSettingChanged();
        summonerRoot.Controls.Add(_summonerEngage, 0, summonerRow);
        summonerRoot.SetColumnSpan(_summonerEngage, 2);
        summonerRow++;
        _summonerRageEnabled = new CheckBox { Text = "Use one Blood Pact: Rage on cooldown", AutoSize = true };
        _summonerRageEnabled.CheckedChanged += (_, _) => OnSummonerSettingChanged();
        summonerRoot.Controls.Add(_summonerRageEnabled, 0, summonerRow);
        summonerRoot.SetColumnSpan(_summonerRageEnabled, 2);
        summonerRow++;
        summonerRoot.Controls.Add(
            new Label { Text = "Rage action", AutoSize = true, Anchor = AnchorStyles.Left },
            0,
            summonerRow
        );
        _summonerRageAction = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Width = 260,
            Anchor = AnchorStyles.Left,
        };
        _summonerRageAction.SelectedIndexChanged += (_, _) => OnSummonerActionChanged();
        summonerRoot.Controls.Add(_summonerRageAction, 1, summonerRow++);
        _summonerRageTargetHppAboveEnabled = new CheckBox
        {
            Text = "Require target HP above",
            AutoSize = true,
        };
        _summonerRageTargetHppAboveEnabled.CheckedChanged += (_, _) => OnSummonerSettingChanged();
        summonerRoot.Controls.Add(_summonerRageTargetHppAboveEnabled, 0, summonerRow);
        _summonerRageTargetHppAbove = new NumericUpDown
        {
            Minimum = 0,
            Maximum = 99,
            Value = 50,
            Width = 90,
            Anchor = AnchorStyles.Left,
        };
        _summonerRageTargetHppAbove.ValueChanged += (_, _) => OnSummonerSettingChanged();
        var summonerTargetHppGate = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
        };
        summonerTargetHppGate.Controls.Add(_summonerRageTargetHppAbove);
        summonerTargetHppGate.Controls.Add(new Label
        {
            Text = "% (exclusive)",
            AutoSize = true,
            Anchor = AnchorStyles.Left,
            Padding = new Padding(0, 5, 0, 0),
        });
        summonerRoot.Controls.Add(summonerTargetHppGate, 1, summonerRow++);
        _summonerRagePetTpAboveEnabled = new CheckBox
        {
            Text = "Require pet TP above",
            AutoSize = true,
        };
        _summonerRagePetTpAboveEnabled.CheckedChanged += (_, _) => OnSummonerSettingChanged();
        summonerRoot.Controls.Add(_summonerRagePetTpAboveEnabled, 0, summonerRow);
        _summonerRagePetTpAbove = new NumericUpDown
        {
            Minimum = 0,
            Maximum = 2999,
            Value = 2000,
            Increment = 100,
            Width = 90,
            Anchor = AnchorStyles.Left,
        };
        _summonerRagePetTpAbove.ValueChanged += (_, _) => OnSummonerSettingChanged();
        summonerRoot.Controls.Add(_summonerRagePetTpAbove, 1, summonerRow++);
        _summonerValidation = new Label
        {
            AutoSize = true,
            MaximumSize = new Size(620, 0),
            Padding = new Padding(0, 8, 0, 0),
        };
        summonerRoot.Controls.Add(_summonerValidation, 0, summonerRow);
        summonerRoot.SetColumnSpan(_summonerValidation, 2);
        _tabSummoner.Controls.Add(summonerRoot);
        _settingsTabs.TabPages.Add(_tabSummoner);

        _tabCor = new TabPage("COR");
        _tabCor.AutoScroll = true;
        var corRoot = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 1,
            Padding = new Padding(8),
        };
        var corRollCfg = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 3,
            Padding = new Padding(0, 0, 0, 8),
        };
        corRollCfg.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 120));
        corRollCfg.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        corRollCfg.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 180));
        corRollCfg.Controls.Add(new Label { Text = "Roll 1", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 0);
        _corRoll1Combo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(180, 0),
        };
        _corRoll1Combo.SelectedIndexChanged += (_, _) => OnCorRollSelected(1);
        corRollCfg.Controls.Add(_corRoll1Combo, 1, 0);
        _corCrookedRoll1 = new CheckBox { Text = "Use Crooked Cards", AutoSize = true, Anchor = AnchorStyles.Left };
        _corCrookedRoll1.CheckedChanged += (_, _) => OnCorCrookedChanged(1, _corCrookedRoll1.Checked);
        corRollCfg.Controls.Add(_corCrookedRoll1, 2, 0);
        corRollCfg.Controls.Add(new Label { Text = "Roll 2", AutoSize = true, Anchor = AnchorStyles.Left }, 0, 1);
        _corRoll2Combo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(180, 0),
        };
        _corRoll2Combo.SelectedIndexChanged += (_, _) => OnCorRollSelected(2);
        corRollCfg.Controls.Add(_corRoll2Combo, 1, 1);
        _corCrookedRoll2 = new CheckBox { Text = "Use Crooked Cards", AutoSize = true, Anchor = AnchorStyles.Left };
        _corCrookedRoll2.CheckedChanged += (_, _) => OnCorCrookedChanged(2, _corCrookedRoll2.Checked);
        corRollCfg.Controls.Add(_corCrookedRoll2, 2, 1);
        corRoot.Controls.Add(corRollCfg);
        var corFlags = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = true };
        _corElevens = new CheckBox { Text = "11's", AutoSize = true };
        _corElevens.CheckedChanged += (_, _) => OnCorFlagChanged("cor_elevens", _corElevens.Checked);
        corFlags.Controls.Add(_corElevens);
        _corLuzafRangeOverride = new CheckBox { Text = "Force Luzaf range (16y)", AutoSize = true };
        _corLuzafRangeOverride.CheckedChanged += (_, _) => OnCorFlagChanged("cor_luzaf_range_override", _corLuzafRangeOverride.Checked);
        corFlags.Controls.Add(_corLuzafRangeOverride);
        corRoot.Controls.Add(corFlags);
        corRoot.Controls.Add(
            new Label
            {
                Text = "Roll range required members (must be in range before rolling):",
                AutoSize = true,
                Padding = new Padding(0, 6, 0, 2),
            }
        );
        _corRangePartyPanel = new FlowLayoutPanel
        {
            AutoSize = true,
            FlowDirection = FlowDirection.TopDown,
            WrapContents = false,
            Dock = DockStyle.Top,
        };
        corRoot.Controls.Add(_corRangePartyPanel);
        _tabCor.Controls.Add(corRoot);
        _settingsTabs.TabPages.Add(_tabCor);

        _tabBrd = new TabPage("BRD Songs") { AutoScroll = true };
        var brdRoot = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 1,
            Padding = new Padding(8),
        };
        _brdEnabled = new CheckBox { Text = "Maintain configured songs", AutoSize = true };
        _brdEnabled.CheckedChanged += (_, _) => OnBrdConfigChanged();
        brdRoot.Controls.Add(_brdEnabled);

        brdRoot.Controls.Add(new Label { Text = "Final songs (ordered)", AutoSize = true, Padding = new Padding(0, 8, 0, 2) });
        _brdSongList = new ListBox { Height = 105, IntegralHeight = false, Dock = DockStyle.Top };
        brdRoot.Controls.Add(_brdSongList);
        var brdSongAddRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        _brdSongCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 280 };
        _brdSongCombo.DropDown += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(_selectedSid)) EnsureOptionsHydrated(_selectedSid, _brdSongOptions.Count == 0);
        };
        _brdSongAdd = new Button { Text = "Add", AutoSize = true };
        _brdSongAdd.Click += (_, _) => OnBrdListAdd(false);
        brdSongAddRow.Controls.Add(_brdSongCombo);
        brdSongAddRow.Controls.Add(_brdSongAdd);
        brdRoot.Controls.Add(brdSongAddRow);
        var brdSongButtons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        _brdSongRemove = new Button { Text = "Remove", AutoSize = true };
        _brdSongRemove.Click += (_, _) => OnBrdListRemove(false);
        _brdSongUp = new Button { Text = "Up", AutoSize = true };
        _brdSongUp.Click += (_, _) => OnBrdListMove(false, -1);
        _brdSongDown = new Button { Text = "Down", AutoSize = true };
        _brdSongDown.Click += (_, _) => OnBrdListMove(false, 1);
        brdSongButtons.Controls.AddRange([_brdSongRemove, _brdSongUp, _brdSongDown]);
        brdRoot.Controls.Add(brdSongButtons);

        brdRoot.Controls.Add(new Label { Text = "Capacity dummy songs (ordered; GearSwap equips the capacity instrument)", AutoSize = true, Padding = new Padding(0, 8, 0, 2) });
        _brdDummyList = new ListBox { Height = 85, IntegralHeight = false, Dock = DockStyle.Top };
        brdRoot.Controls.Add(_brdDummyList);
        var brdDummyAddRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        _brdDummyCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 280 };
        _brdDummyCombo.DropDown += (_, _) =>
        {
            if (!string.IsNullOrWhiteSpace(_selectedSid)) EnsureOptionsHydrated(_selectedSid, _brdSongOptions.Count == 0);
        };
        _brdDummyAdd = new Button { Text = "Add", AutoSize = true };
        _brdDummyAdd.Click += (_, _) => OnBrdListAdd(true);
        brdDummyAddRow.Controls.Add(_brdDummyCombo);
        brdDummyAddRow.Controls.Add(_brdDummyAdd);
        brdRoot.Controls.Add(brdDummyAddRow);
        var brdDummyButtons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        _brdDummyRemove = new Button { Text = "Remove", AutoSize = true };
        _brdDummyRemove.Click += (_, _) => OnBrdListRemove(true);
        _brdDummyUp = new Button { Text = "Up", AutoSize = true };
        _brdDummyUp.Click += (_, _) => OnBrdListMove(true, -1);
        _brdDummyDown = new Button { Text = "Down", AutoSize = true };
        _brdDummyDown.Click += (_, _) => OnBrdListMove(true, 1);
        brdDummyButtons.Controls.AddRange([_brdDummyRemove, _brdDummyUp, _brdDummyDown]);
        brdRoot.Controls.Add(brdDummyButtons);

        var brdFlags = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = true, Padding = new Padding(0, 8, 0, 0) };
        _brdUseNitro = new CheckBox { Text = "Use NITRO (Nightingale + Troubadour)", AutoSize = true };
        _brdUseNitro.CheckedChanged += (_, _) => OnBrdConfigChanged();
		_brdUseSoulVoice = new CheckBox { Text = "Use Soul Voice (requires NITRO)", AutoSize = true };
		_brdUseSoulVoice.CheckedChanged += (_, _) => OnBrdConfigChanged();
        _brdUseClarion = new CheckBox { Text = "Use Clarion Call", AutoSize = true };
        _brdUseClarion.CheckedChanged += (_, _) => OnBrdConfigChanged();
        _brdUseMarcato = new CheckBox { Text = "Use Marcato", AutoSize = true };
        _brdUseMarcato.CheckedChanged += (_, _) => OnBrdConfigChanged();
        brdFlags.Controls.AddRange([_brdUseNitro, _brdUseSoulVoice, _brdUseClarion, _brdUseMarcato]);
        brdRoot.Controls.Add(brdFlags);
        var marcatoRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        marcatoRow.Controls.Add(new Label { Text = "Marcato song", AutoSize = true, Padding = new Padding(0, 5, 8, 0) });
        _brdMarcatoSong = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 280 };
        _brdMarcatoSong.SelectedIndexChanged += (_, _) => OnBrdConfigChanged();
        marcatoRow.Controls.Add(_brdMarcatoSong);
        brdRoot.Controls.Add(marcatoRow);
		var recoveryRangeRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, Padding = new Padding(0, 8, 0, 0) };
		recoveryRangeRow.Controls.Add(new Label { Text = "Recovery range (yalms)", AutoSize = true, Padding = new Padding(0, 5, 8, 0) });
		_brdRecoveryRangeYalms = new NumericUpDown
		{
			Minimum = 1.0m,
			Maximum = 20.0m,
			Value = 9.9m,
			Increment = 0.1m,
			DecimalPlaces = 1,
			Width = 80,
		};
		_brdRecoveryRangeYalms.ValueChanged += (_, _) => OnBrdConfigChanged();
		recoveryRangeRow.Controls.Add(_brdRecoveryRangeYalms);
		brdRoot.Controls.Add(recoveryRangeRow);
		brdRoot.Controls.Add(new Label { Text = "Set to the equipped song instrument's actual area radius. Ordinary horn setups use 9.9; string instruments may support a larger tested radius.", AutoSize = true });
		_brdRepositionForPartySongs = new CheckBox
		{
			Text = "Reposition to cover the party for group songs",
			AutoSize = true,
			Padding = new Padding(0, 8, 0, 0),
		};
		_brdRepositionForPartySongs.CheckedChanged += (_, _) => OnBrdConfigChanged();
		brdRoot.Controls.Add(_brdRepositionForPartySongs);
		brdRoot.Controls.Add(new Label { Text = "Moves to a camp-safe shared casting point before group maintenance. Waits when no full-party point exists unless a song is urgently expiring; capacity and dummy work always requires full coverage.", AutoSize = true });
		var recoveryIgnoreRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, Padding = new Padding(0, 8, 0, 0) };
		recoveryIgnoreRow.Controls.Add(new Label { Text = "Recovery ignore players", AutoSize = true, Padding = new Padding(0, 5, 8, 0) });
		_brdRecoveryIgnoreNames = new TextBox { Width = 280 };
		_brdRecoveryIgnoreNames.TextChanged += (_, _) => OnBrdConfigChanged();
		recoveryIgnoreRow.Controls.Add(_brdRecoveryIgnoreNames);
		brdRoot.Controls.Add(recoveryIgnoreRow);
		brdRoot.Controls.Add(new Label { Text = "Pipe-separated names. Ignored players never trigger song recovery after returning to range.", AutoSize = true });
		var targetedSongsRow = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false, Padding = new Padding(0, 8, 0, 0) };
		targetedSongsRow.Controls.Add(new Label { Text = "Pianissimo overlays", AutoSize = true, Padding = new Padding(0, 5, 8, 0) });
		_brdTargetedSongs = new TextBox { Width = 460 };
		_brdTargetedSongs.TextChanged += (_, _) => OnBrdConfigChanged();
		targetedSongsRow.Controls.Add(_brdTargetedSongs);
		brdRoot.Controls.Add(targetedSongsRow);
		brdRoot.Controls.Add(new Label { Text = "TargetA,TargetB:Highest Priority Song,Next Song|OtherTarget:Song", AutoSize = true });
        brdRoot.Controls.Add(new Label
        {
            Text = "Durations and active song ownership are observed by the addon and are never saved in the profile.",
            AutoSize = true,
            Padding = new Padding(0, 10, 0, 0),
        });
        _tabBrd.Controls.Add(brdRoot);
        _settingsTabs.TabPages.Add(_tabBrd);

        var tabReactions = new TabPage("Reactions") { AutoScroll = true };
        var reactionRoot = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 1,
            Padding = new Padding(8),
        };
        _reactionEnabled = new CheckBox { Text = "Enable configured reactions", AutoSize = true };
        _reactionEnabled.CheckedChanged += (_, _) => OnReactionConfigChanged();
        reactionRoot.Controls.Add(_reactionEnabled);
        reactionRoot.Controls.Add(new Label
        {
            Text = "Reactions apply only to the current combat target. Active actor IDs and reaction locks are runtime-only.",
            AutoSize = true,
            Padding = new Padding(0, 5, 0, 8),
        });
        _reactionRuleList = new ListBox { Height = 140, IntegralHeight = false, Dock = DockStyle.Top };
        reactionRoot.Controls.Add(_reactionRuleList);
        var reactionEditor = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 4,
            Padding = new Padding(0, 8, 0, 0),
        };
        reactionEditor.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 135));
        reactionEditor.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f));
        reactionEditor.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 145));
        reactionEditor.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 70));
        _reactionTriggerCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
        _reactionTriggerCombo.Items.AddRange(["ability_window", "enemy_buff"]);
        _reactionTriggerCombo.SelectedIndexChanged += (_, _) => OnReactionTriggerChanged();
        _reactionName = new TextBox { Dock = DockStyle.Fill, PlaceholderText = "Cold Stare" };
        _reactionResponseCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Fill };
        _reactionAdd = new Button { Text = "Add", AutoSize = true };
        _reactionAdd.Click += (_, _) => OnReactionRuleAdd();
        reactionEditor.Controls.Add(_reactionTriggerCombo, 0, 0);
        reactionEditor.Controls.Add(_reactionName, 1, 0);
        reactionEditor.Controls.Add(_reactionResponseCombo, 2, 0);
        reactionEditor.Controls.Add(_reactionAdd, 3, 0);
        reactionRoot.Controls.Add(reactionEditor);
        var reactionButtons = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = false };
        _reactionRemove = new Button { Text = "Remove", AutoSize = true };
        _reactionRemove.Click += (_, _) => OnReactionRuleRemove();
        _reactionUp = new Button { Text = "Up", AutoSize = true };
        _reactionUp.Click += (_, _) => OnReactionRuleMove(-1);
        _reactionDown = new Button { Text = "Down", AutoSize = true };
        _reactionDown.Click += (_, _) => OnReactionRuleMove(1);
        reactionButtons.Controls.AddRange([_reactionRemove, _reactionUp, _reactionDown]);
        reactionRoot.Controls.Add(reactionButtons);
        reactionRoot.Controls.Add(new Label
        {
            Text = "ability_window turns away from ready until completion. enemy_buff holds attacks while the named enemy effect is active.",
            AutoSize = true,
            Padding = new Padding(0, 8, 0, 0),
        });
        tabReactions.Controls.Add(reactionRoot);
        _settingsTabs.TabPages.Add(tabReactions);
        _reactionTriggerCombo.SelectedItem = "ability_window";

        var tabScheduler = new TabPage("Scheduler");
        tabScheduler.AutoScroll = true;
        var sch = new TableLayoutPanel
        {
            AutoSize = true,
            Dock = DockStyle.Top,
            ColumnCount = 1,
            Padding = new Padding(8),
        };
        sch.Controls.Add(
            new Label
            {
                Text = "Runtime domains: these settings authoritatively enable participation. Save the profile and reload/apply profile v2 for changes to take effect.",
                AutoSize = true,
                Padding = new Padding(0, 0, 0, 8),
            }
        );
        sch.Controls.Add(MkGlobal("domain_combat_enabled"));
        sch.Controls.Add(MkGlobal("domain_defensive_enabled"));
        sch.Controls.Add(MkGlobal("domain_movement_enabled"));
        sch.Controls.Add(MkGlobal("domain_maintenance_enabled"));
        sch.Controls.Add(MkGlobal("domain_follow_enabled"));
        tabScheduler.Controls.Add(sch);
        _settingsTabs.TabPages.Add(tabScheduler);

        form.Controls.Add(_settingsTabs);
        root.Controls.Add(form, 0, 1);

        _btnSave = new Button { Text = "Save (XML)", AutoSize = false };
        _btnSave.Click += (_, _) => SaveRemote();
        _btnToggleEngine = new Button { Text = "Toggle engine run", AutoSize = false };
        _btnToggleEngine.Click += (_, _) => ToggleEngine();
        _btnReloadAddon = new Button { Text = "Reload addon (+reapply run)", AutoSize = false };
        _btnReloadAddon.Click += (_, _) => ReloadAddonAndReapplyRun();
        sessionActionsFooter.Controls.AddRange(new Control[] { _btnSave, _btnToggleEngine, _btnReloadAddon });
        void sizeSessionButtons()
        {
            var w = Math.Max(120, sessionActionsFooter.ClientSize.Width - sessionActionsFooter.Padding.Horizontal - 2);
            foreach (var b in new[] { _btnSave, _btnToggleEngine, _btnReloadAddon })
            {
                b.Width = w;
                b.Margin = new Padding(0, 0, 0, 6);
            }
        }
        sessionActionsFooter.SizeChanged += (_, _) => sizeSessionButtons();
        sizeSessionButtons();

        CheckBox MkCtx(string key)
        {
            var cb = new CheckBox { Text = HubUiConstants.BoolLabel(key), AutoSize = true };
            _boolChecks[key] = cb;
            cb.CheckedChanged += (_, _) => OnAnyBool(key, cb.Checked);
            return cb;
        }

        CheckBox MkGlobal(string key)
        {
            var cb = new CheckBox { Text = HubUiConstants.BoolLabel(key), AutoSize = true };
            _boolChecks[key] = cb;
            cb.CheckedChanged += (_, _) => OnAnyBool(key, cb.Checked);
            return cb;
        }

    }

    private IEnumerable<NumericUpDown> FormationNumericControls()
    {
        return
        [
            _formationCaptureStable,
            _formationCaptureTolerance,
            _formationSafeRadius,
            _formationTankAcceptRadius,
            _formationTankReturnRadius,
            _formationDpsFlankAngle,
            _formationDpsMeleeRadius,
            _formationDpsPositionTolerance,
            _formationHealerPreferredRadius,
            _formationHealerMinimumBossDistance,
            _formationHealerMaximumPartyRange,
            _formationHealerConeHalfAngle,
            _formationHealerConeSafetyMargin,
            _formationHealerSampleStep,
        ];
    }

    private static NumericUpDown CreateFormationNumber(decimal minimum, decimal maximum, decimal value, decimal increment, int decimalPlaces)
    {
        return new NumericUpDown
        {
            Minimum = minimum,
            Maximum = maximum,
            Value = value,
            Increment = increment,
            DecimalPlaces = decimalPlaces,
            Width = 100,
            ThousandsSeparator = false,
        };
    }

    private static void AddFormationNumberRow(TableLayoutPanel panel, string label, NumericUpDown control, ref int row)
    {
        panel.Controls.Add(new Label { Text = label, AutoSize = true, Anchor = AnchorStyles.Left }, 0, row);
        panel.Controls.Add(control, 1, row++);
    }

    private static void AddFormationSectionLabel(TableLayoutPanel panel, string text, ref int row)
    {
        var label = new Label
        {
            Text = text,
            AutoSize = true,
            Font = new Font(SystemFonts.DefaultFont, FontStyle.Bold),
            Padding = new Padding(0, 10, 0, 3),
        };
        panel.Controls.Add(label, 0, row);
        panel.SetColumnSpan(label, 2);
        row++;
    }

    private GroupBox CreateBoolCard(string title, IEnumerable<string> keys)
    {
        var gb = new GroupBox
        {
            Text = title,
            Dock = DockStyle.Fill,
            Padding = new Padding(8),
            AutoSize = true,
        };
        var t = new TableLayoutPanel { AutoSize = true, Dock = DockStyle.Top, ColumnCount = 1 };
        foreach (var key in keys)
        {
            var cb = new CheckBox { Text = HubUiConstants.BoolLabel(key), AutoSize = true, Anchor = AnchorStyles.Left };
            _boolChecks[key] = cb;
            cb.CheckedChanged += (_, _) => OnAnyBool(key, cb.Checked);
            t.Controls.Add(cb);
        }

        if (title.StartsWith("Healer", StringComparison.Ordinal))
        {
            t.Controls.Add(
                new Label
                {
                    Text = "When Healer Enabled is off, options stay editable but inactive.",
                    AutoSize = true,
                    ForeColor = SystemColors.GrayText,
                }
            );
        }

        gb.Controls.Add(t);
        return gb;
    }
}
