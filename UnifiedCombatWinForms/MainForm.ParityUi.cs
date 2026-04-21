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
    private ComboBox _aftermathCombo = null!;
    private ComboBox _pullerCombo = null!;
    private ComboBox _fightLeaderCombo = null!;
    private ComboBox _partyFollowCombo = null!;
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
    private TextBox _defOverwrite = null!;
    private TextBox _defBuffs = null!;
    private Label _lblBlock = null!;
    private Label _lblSched = null!;
    private Label _lblSchedProv = null!;
    private Label _lblTick = null!;
    private Label _lblWsDiag = null!;
    private GroupBox _grpFightLeader = null!;
    private Label _lblFightLeaderOp = null!;
    private Label _lblPartyFollowOp = null!;
    private GroupBox _grpAddPri = null!;
    private ListBox _addPriList = null!;
    private TextBox _addPriName = null!;
    private Button _addPriByName = null!;
    private Button _addPriCurTarget = null!;
    private Button _addPriRemove = null!;
    private Button _addPriUp = null!;
    private Button _addPriDown = null!;
    private Label _lblAddPriOp = null!;
    private GroupBox _grpPartner = null!;
    private ListBox _partnerList = null!;
    private TextBox _partnerName = null!;
    private Button _partnerByName = null!;
    private Button _partnerCurTarget = null!;
    private Button _partnerRemove = null!;
    private Label _lblPartnerOp = null!;
    private GroupBox _grpIgnore = null!;
    private ListBox _ignoreList = null!;
    private TextBox _ignoreName = null!;
    private Button _ignoreByName = null!;
    private Button _ignoreCurTarget = null!;
    private Button _ignoreRemove = null!;
    private Label _lblIgnoreInfo = null!;
    private Label _lblIgnoreOp = null!;
    private GroupBox _grpTargetIgn = null!;
    private ListBox _targetIgnList = null!;
    private TextBox _targetIgnName = null!;
    private Button _targetIgnByName = null!;
    private Button _targetIgnCurTarget = null!;
    private Button _targetIgnRemove = null!;
    private Label _lblTargetIgnOp = null!;
    private Button _btnSave = null!;
    private Button _btnToggleEngine = null!;
    private CheckBox _spUsePrediction = null!;
    private TextBox _spBandMin = null!;
    private TextBox _spBandMax = null!;
    private TextBox _spLookahead = null!;
    private TextBox _spAnchorInvalidTicks = null!;
    private TextBox _spEmergencyMargin = null!;
    private TextBox _spSwitchPenalty = null!;
    private TextBox _spSwitchMargin = null!;
    private TextBox _spArrivalTolerance = null!;
    private TextBox _spMaxAgents = null!;

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
            DropDownStyle = ComboBoxStyle.DropDownList,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(120, 0),
        };
        _wsCombo.SelectedIndexChanged += (_, _) => OnWsSelected();
        leftCol.Controls.Add(_wsCombo, 1, lr);
        lr++;

        _chkAftermath = MkCtx("aftermath_enabled");
        leftCol.Controls.Add(_chkAftermath, 0, lr);
        _aftermathCombo = new ComboBox
        {
            DropDownStyle = ComboBoxStyle.DropDownList,
            Anchor = AnchorStyles.Left | AnchorStyles.Right | AnchorStyles.Top,
            MinimumSize = new Size(120, 0),
        };
        _aftermathCombo.SelectedIndexChanged += (_, _) => OnAftermathWsSelected();
        leftCol.Controls.Add(_aftermathCombo, 1, lr);
        lr++;

        var abPick = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        _chkAbility = MkCtx("ability_active");
        leftCol.Controls.Add(_chkAbility, 0, lr);
        _abilityPickCombo = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Width = 220 };
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

        topSplit.Controls.Add(leftCol, 0, 0);
        topSplit.Controls.Add(rightCol, 1, 0);
        g.Controls.Add(topSplit, 0, gRow++);

        var diag = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, WrapContents = true };
        diag.Controls.Add(new Label { Text = "block_reason:", AutoSize = true });
        diag.Controls.Add(_lblBlock = new Label { AutoSize = true, Text = "" });
        diag.Controls.Add(new Label { Text = "scheduler_action:", AutoSize = true, Padding = new Padding(10, 0, 0, 0) });
        diag.Controls.Add(_lblSched = new Label { AutoSize = true, Text = "" });
        diag.Controls.Add(new Label { Text = "provider:", AutoSize = true });
        diag.Controls.Add(_lblSchedProv = new Label { AutoSize = true, Text = "" });
        diag.Controls.Add(new Label { Text = "tick:", AutoSize = true });
        diag.Controls.Add(_lblTick = new Label { AutoSize = true, Text = "" });
        g.Controls.Add(diag, 0, gRow++);
        diag.Dock = DockStyle.Top;

        var diagWs = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight };
        diagWs.Controls.Add(new Label { Text = "ws_diag:", AutoSize = true });
        diagWs.Controls.Add(_lblWsDiag = new Label { AutoSize = true, Text = "" });
        g.Controls.Add(diagWs, 0, gRow++);
        diagWs.Dock = DockStyle.Top;

        _grpFightLeader = new GroupBox
        {
            Text = "Fight leader — autotarget prefers leader target; add control uses priority list.",
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
        _lblFightLeaderOp = new Label { AutoSize = true, Text = "" };
        flFlow.Controls.Add(_lblFightLeaderOp);
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
        _lblPartyFollowOp = new Label { AutoSize = true, Text = "" };
        flFlow.Controls.Add(_lblPartyFollowOp);
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

        _grpAddPri = new GroupBox
        {
            Text = "Fight-add priority — ordered mob names; Up/Down reorders.",
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
        _lblAddPriOp = new Label { AutoSize = true, Text = "", Padding = new Padding(0, 6, 0, 0) };
        apFlow.Controls.Add(_lblAddPriOp);
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
        _lblPartnerOp = new Label { AutoSize = true, Text = "", Padding = new Padding(0, 6, 0, 0) };
        pFlow.Controls.Add(_lblPartnerOp);
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
        var ignInf = new FlowLayoutPanel { AutoSize = true, FlowDirection = FlowDirection.LeftToRight, Padding = new Padding(0, 6, 0, 0) };
        ignInf.Controls.Add(_lblIgnoreInfo = new Label { AutoSize = true, Text = "" });
        ignInf.Controls.Add(_lblIgnoreOp = new Label { AutoSize = true, Text = "", Padding = new Padding(16, 0, 0, 0) });
        iFlow.Controls.Add(ignInf);
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
        _lblTargetIgnOp = new Label { AutoSize = true, Text = "", Padding = new Padding(0, 6, 0, 0) };
        tiFlow.Controls.Add(_lblTargetIgnOp);
        _grpTargetIgn.Controls.Add(tiFlow);
        listsSplit.Controls.Add(_grpTargetIgn, 1, 1);

        g.Controls.Add(listsSplit, 0, gRow++);

        var tabs = new TabControl
        {
            Dock = DockStyle.Top,
            Height = 520,
        };
        var tabGeneral = new TabPage("General");
        tabGeneral.AutoScroll = true;
        g.Dock = DockStyle.Top;
        tabGeneral.Controls.Add(g);
        tabs.TabPages.Add(tabGeneral);

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
        sp.Controls.Add(new Label { Text = "Comfort band min (real)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spBandMin = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spBandMin.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spBandMin, 1, sr++);
        sp.Controls.Add(new Label { Text = "Comfort band max (real)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spBandMax = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spBandMax.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spBandMax, 1, sr++);
        sp.Controls.Add(new Label { Text = "Prediction lookahead (s)", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spLookahead = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spLookahead.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spLookahead, 1, sr++);
        sp.Controls.Add(new Label { Text = "Anchor invalid ticks", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spAnchorInvalidTicks = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spAnchorInvalidTicks.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spAnchorInvalidTicks, 1, sr++);
        sp.Controls.Add(new Label { Text = "Emergency margin", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spEmergencyMargin = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spEmergencyMargin.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spEmergencyMargin, 1, sr++);
        sp.Controls.Add(new Label { Text = "Slot switch penalty", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spSwitchPenalty = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spSwitchPenalty.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spSwitchPenalty, 1, sr++);
        sp.Controls.Add(new Label { Text = "Slot switch margin", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spSwitchMargin = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spSwitchMargin.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spSwitchMargin, 1, sr++);
        sp.Controls.Add(new Label { Text = "Slot arrival tolerance", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spArrivalTolerance = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spArrivalTolerance.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spArrivalTolerance, 1, sr++);
        sp.Controls.Add(new Label { Text = "Max agents", AutoSize = true, Anchor = AnchorStyles.Left }, 0, sr);
        _spMaxAgents = new TextBox { Width = 90, Anchor = AnchorStyles.Left };
        _spMaxAgents.Leave += (_, _) => OnSpacingTuningNumericChanged();
        sp.Controls.Add(_spMaxAgents, 1, sr++);
        tabSpacing.Controls.Add(sp);
        tabs.TabPages.Add(tabSpacing);

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
        tabScheduler.Controls.Add(sch);
        tabs.TabPages.Add(tabScheduler);

        form.Controls.Add(tabs);
        root.Controls.Add(form, 0, 1);

        _btnSave = new Button { Text = "Save (XML)", AutoSize = true };
        _btnSave.Click += (_, _) => SaveRemote();
        _btnToggleEngine = new Button { Text = "Toggle engine run", AutoSize = true };
        _btnToggleEngine.Click += (_, _) => ToggleEngine();
        sessionActionsFooter.Controls.AddRange(new Control[] { _btnSave, _btnToggleEngine });

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
