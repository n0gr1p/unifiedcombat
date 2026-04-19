namespace UnifiedCombatWinForms;

partial class MainForm
{
    private System.ComponentModel.IContainer components = null!;

    private MenuStrip menuStrip;
    private ToolStripMenuItem fileToolStripMenuItem;
    private ToolStripMenuItem exitToolStripMenuItem;
    private StatusStrip statusStrip;
    private ToolStripStatusLabel statusConnection;
    private ToolStripStatusLabel statusLastUpdate;
    private SplitContainer splitContainer;
    private Panel panelSessionColumn;
    private TableLayoutPanel tableSessionSidebar;
    private Label labelSessionsHeader;
    private FlowLayoutPanel flowSessionActions;
    private ListBox listSessions;
    private Panel panelEditorHost;

    protected override void Dispose(bool disposing)
    {
        if (disposing && components != null)
        {
            components.Dispose();
        }
        base.Dispose(disposing);
    }

    private void InitializeComponent()
    {
        components = new System.ComponentModel.Container();
        menuStrip = new MenuStrip();
        fileToolStripMenuItem = new ToolStripMenuItem();
        exitToolStripMenuItem = new ToolStripMenuItem();
        statusStrip = new StatusStrip();
        statusConnection = new ToolStripStatusLabel();
        statusLastUpdate = new ToolStripStatusLabel();
        splitContainer = new SplitContainer();
        panelSessionColumn = new Panel();
        tableSessionSidebar = new TableLayoutPanel();
        labelSessionsHeader = new Label();
        flowSessionActions = new FlowLayoutPanel();
        listSessions = new ListBox();
        panelEditorHost = new Panel();
        menuStrip.SuspendLayout();
        statusStrip.SuspendLayout();
        ((System.ComponentModel.ISupportInitialize)splitContainer).BeginInit();
        splitContainer.Panel1.SuspendLayout();
        splitContainer.Panel2.SuspendLayout();
        splitContainer.SuspendLayout();
        panelSessionColumn.SuspendLayout();
        tableSessionSidebar.SuspendLayout();
        SuspendLayout();
        //
        // menuStrip
        //
        menuStrip.Items.AddRange(new ToolStripItem[] { fileToolStripMenuItem });
        menuStrip.Location = new Point(0, 0);
        menuStrip.Name = "menuStrip";
        menuStrip.Size = new Size(1184, 24);
        menuStrip.TabIndex = 0;
        //
        // fileToolStripMenuItem
        //
        fileToolStripMenuItem.DropDownItems.AddRange(new ToolStripItem[] { exitToolStripMenuItem });
        fileToolStripMenuItem.Name = "fileToolStripMenuItem";
        fileToolStripMenuItem.Size = new Size(37, 20);
        fileToolStripMenuItem.Text = "&File";
        //
        // exitToolStripMenuItem
        //
        exitToolStripMenuItem.Name = "exitToolStripMenuItem";
        exitToolStripMenuItem.Size = new Size(93, 22);
        exitToolStripMenuItem.Text = "E&xit";
        exitToolStripMenuItem.Click += (_, _) => Close();
        //
        // statusStrip
        //
        statusStrip.Items.AddRange(new ToolStripItem[] { statusConnection, statusLastUpdate });
        statusStrip.Location = new Point(0, 739);
        statusStrip.Name = "statusStrip";
        statusStrip.Size = new Size(1184, 22);
        statusStrip.TabIndex = 1;
        //
        // statusConnection
        //
        statusConnection.Name = "statusConnection";
        statusConnection.Size = new Size(180, 17);
        statusConnection.Text = "Mirror: connecting…";
        //
        // statusLastUpdate
        //
        statusLastUpdate.Name = "statusLastUpdate";
        statusLastUpdate.Size = new Size(987, 17);
        statusLastUpdate.Spring = true;
        statusLastUpdate.TextAlign = ContentAlignment.MiddleLeft;
        //
        // splitContainer
        //
        splitContainer.Dock = DockStyle.Fill;
        splitContainer.FixedPanel = FixedPanel.Panel1;
        splitContainer.Location = new Point(0, 24);
        splitContainer.Name = "splitContainer";
        splitContainer.Panel1.Controls.Add(panelSessionColumn);
        splitContainer.Panel2.Controls.Add(panelEditorHost);
        splitContainer.Size = new Size(1184, 715);
        splitContainer.SplitterDistance = 260;
        splitContainer.TabIndex = 2;
        //
        // panelSessionColumn
        //
        panelSessionColumn.Dock = DockStyle.Fill;
        panelSessionColumn.Name = "panelSessionColumn";
        panelSessionColumn.Padding = new Padding(4, 4, 4, 0);
        panelSessionColumn.Controls.Add(tableSessionSidebar);
        //
        // tableSessionSidebar
        //
        tableSessionSidebar.ColumnCount = 1;
        tableSessionSidebar.Dock = DockStyle.Fill;
        tableSessionSidebar.Name = "tableSessionSidebar";
        tableSessionSidebar.Padding = new Padding(0);
        tableSessionSidebar.RowCount = 3;
        tableSessionSidebar.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        tableSessionSidebar.RowStyles.Add(new RowStyle(SizeType.Percent, 100F));
        tableSessionSidebar.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        tableSessionSidebar.Controls.Add(labelSessionsHeader, 0, 0);
        tableSessionSidebar.Controls.Add(listSessions, 0, 1);
        tableSessionSidebar.Controls.Add(flowSessionActions, 0, 2);
        //
        // labelSessionsHeader
        //
        labelSessionsHeader.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
        labelSessionsHeader.AutoSize = true;
        labelSessionsHeader.Font = new Font("Segoe UI", 9F, FontStyle.Bold, GraphicsUnit.Point);
        labelSessionsHeader.Margin = new Padding(4, 4, 4, 6);
        labelSessionsHeader.Name = "labelSessionsHeader";
        labelSessionsHeader.Padding = new Padding(2, 2, 2, 0);
        labelSessionsHeader.Text = "Sessions";
        labelSessionsHeader.TextAlign = ContentAlignment.MiddleLeft;
        //
        // flowSessionActions
        //
        flowSessionActions.AutoSize = true;
        flowSessionActions.AutoSizeMode = AutoSizeMode.GrowAndShrink;
        flowSessionActions.Dock = DockStyle.Fill;
        flowSessionActions.FlowDirection = FlowDirection.LeftToRight;
        flowSessionActions.Margin = new Padding(0, 6, 0, 0);
        flowSessionActions.Name = "flowSessionActions";
        flowSessionActions.Padding = new Padding(4, 6, 4, 8);
        flowSessionActions.WrapContents = true;
        //
        // listSessions
        //
        listSessions.Dock = DockStyle.Fill;
        listSessions.IntegralHeight = false;
        listSessions.Margin = new Padding(0, 2, 0, 0);
        listSessions.Name = "listSessions";
        listSessions.TabIndex = 0;
        listSessions.SelectedIndexChanged += ListSessions_SelectedIndexChanged;
        //
        // panelEditorHost
        //
        panelEditorHost.AutoScroll = true;
        panelEditorHost.Dock = DockStyle.Fill;
        panelEditorHost.Name = "panelEditorHost";
        panelEditorHost.TabIndex = 0;
        //
        // MainForm
        //
        AutoScaleDimensions = new SizeF(7F, 15F);
        AutoScaleMode = AutoScaleMode.Font;
        ClientSize = new Size(1184, 761);
        Controls.Add(splitContainer);
        Controls.Add(statusStrip);
        Controls.Add(menuStrip);
        MainMenuStrip = menuStrip;
        MinimumSize = new Size(900, 600);
        Name = "MainForm";
        StartPosition = FormStartPosition.CenterScreen;
        Text = "UnifiedCombat — desktop UI (hub UI channel 127.0.0.1:27183)";
        menuStrip.ResumeLayout(false);
        menuStrip.PerformLayout();
        statusStrip.ResumeLayout(false);
        statusStrip.PerformLayout();
        splitContainer.Panel1.ResumeLayout(false);
        splitContainer.Panel2.ResumeLayout(false);
        ((System.ComponentModel.ISupportInitialize)splitContainer).EndInit();
        splitContainer.ResumeLayout(false);
        panelSessionColumn.ResumeLayout(false);
        tableSessionSidebar.ResumeLayout(false);
        tableSessionSidebar.PerformLayout();
        ResumeLayout(false);
        PerformLayout();
    }
}
