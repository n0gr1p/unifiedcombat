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
    private ComboBox _aftermathCombo = null!;
    private ComboBox _pullerCombo = null!;
    private ComboBox _fightLeaderCombo = null!;
    private ComboBox _partyFollowCombo = null!;
    private Label _partyFollowModeWarning = null!;
    private TextBox _pfFollowMinYalms = null!;
    private TextBox _pfFollowMaxYalms = null!;
    private TextBox _pfFightFollowMinYalms = null!;
    private TextBox _pfFightFollowHoldS = null!;
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
    private TabControl _settingsTabs = null!;
    private TabPage _tabCor = null!;
    private ComboBox _corRoll1Combo = null!;
    private ComboBox _corRoll2Combo = null!;
    private CheckBox _corCrookedRoll1 = null!;
    private CheckBox _corCrookedRoll2 = null!;
    private CheckBox _corElevens = null!;
    private CheckBox _corLuzafRangeOverride = null!;
    private FlowLayoutPanel _corRangePartyPanel = null!;
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
        _pullerCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 };
        _pullerCombo.SelectedIndexChanged += (_, _) => OnPullerSelected();
        pull.Controls.Add(_pullerCombo);
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
                Text = "Dark-launch toggles: opt into scheduler-owned dispatch paths per session.",
                AutoSize = true,
                Padding = new Padding(0, 0, 0, 8),
            }
        );
        sch.Controls.Add(MkGlobal("scheduler_dark_launch_combat"));
        sch.Controls.Add(MkGlobal("scheduler_dark_launch_defensive"));
        sch.Controls.Add(MkGlobal("scheduler_dark_launch_movement"));
        sch.Controls.Add(MkGlobal("scheduler_dark_launch_maintenance"));
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
