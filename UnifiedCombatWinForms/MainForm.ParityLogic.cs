using System.Globalization;
using System.Text.Json;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private static bool SequenceEqualOrdinal(IReadOnlyList<string> a, IReadOnlyList<string> b)
    {
        if (a.Count != b.Count)
        {
            return false;
        }

        for (var i = 0; i < a.Count; i++)
        {
            if (!string.Equals(a[i], b[i], StringComparison.Ordinal))
            {
                return false;
            }
        }

        return true;
    }

    private static List<string> ComputeSelectedAbilitiesFromState(JsonElement s, IReadOnlyList<string> abilityOptions)
    {
        var sel = SessionStateHelper.SplitOptions(s.TryGetProperty("abilities_selected", out var asel) ? asel : default);
        if (sel.Count == 0)
        {
            for (var i = 1; i <= 6; i++)
            {
                var v = SessionStateHelper.GetString(s, "ability" + i);
                if (!string.IsNullOrEmpty(v))
                {
                    sel.Add(v);
                }
            }
        }

        var outl = new List<string>();
        foreach (var a in sel)
        {
            if (string.IsNullOrEmpty(a))
            {
                continue;
            }

            if (!abilityOptions.Any(o => string.Equals(o, a, StringComparison.Ordinal)))
            {
                continue;
            }

            if (outl.Any(x => string.Equals(x, a, StringComparison.Ordinal)))
            {
                continue;
            }

            outl.Add(a);
        }

        return outl;
    }

    private void RefreshEditorFromSnapshot()
    {
        if (_snapshotDoc is null || string.IsNullOrEmpty(_selectedSid))
        {
            ClearForm();
            return;
        }

        if (!_snapshotDoc.RootElement.TryGetProperty("sessions", out var sessions) || sessions.ValueKind != JsonValueKind.Object)
        {
            ClearForm();
            return;
        }

        if (!sessions.TryGetProperty(_selectedSid, out var s))
        {
            ClearForm();
            return;
        }

        PrunePendingBoolEchoes(_selectedSid, s);

        if (_pendingWsBySid.TryGetValue(_selectedSid, out var pws))
        {
            var eng = SessionStateHelper.GetString(s, "engine", "melee");
            var incomingWs = SessionStateHelper.WsFromState(s, eng);
            if (incomingWs == pws.ws)
            {
                _pendingWsBySid.Remove(_selectedSid);
            }
            else if ((DateTime.UtcNow - pws.ts).TotalSeconds < 3)
            {
                SetWsComboOnly(pws.ws, s, eng);
                RenderAuxLists(s);
                return;
            }
            else
            {
                _pendingWsBySid.Remove(_selectedSid);
            }
        }

        if ((DateTime.UtcNow - _abilityInteractionUtc).TotalSeconds < 2.0)
        {
            var eng = SessionStateHelper.GetString(s, "engine", "melee");
            var wsv = SessionStateHelper.WsFromState(s, eng);
            SetWsComboOnly(wsv, s, eng);
            RenderAuxLists(s);
            return;
        }

        FillFromSession(_selectedSid, s);
    }

    private void PrunePendingBoolEchoes(string sid, JsonElement s)
    {
        if (!_pendingBoolBySid.TryGetValue(sid, out var pend))
        {
            return;
        }

        var now = DateTime.UtcNow;
        foreach (var key in pend.Keys.ToList())
        {
            var (val, ts) = pend[key];
            var incoming = SessionStateHelper.GetBool(s, key, false);
            if (incoming == val)
            {
                pend.Remove(key);
            }
            else if ((now - ts).TotalSeconds >= 3)
            {
                pend.Remove(key);
            }
        }

        if (pend.Count == 0)
        {
            _pendingBoolBySid.Remove(sid);
        }
    }

    private void SetWsComboOnly(string wsVal, JsonElement s, string eng)
    {
        _suppressEvents = true;
        try
        {
            var opts = SessionStateHelper.SplitOptions(s.TryGetProperty("weaponskill_options", out var wo) ? wo : default);
            var list = new List<string>(opts);
            if (!string.IsNullOrEmpty(wsVal) && !list.Contains(wsVal))
            {
                list.Insert(0, wsVal);
            }

            _wsCombo.Items.Clear();
            foreach (var o in list)
            {
                _wsCombo.Items.Add(o);
            }

            var idx = list.IndexOf(wsVal);
            _wsCombo.SelectedIndex = idx >= 0 ? idx : (list.Count > 0 ? 0 : -1);
            var amVal = SessionStateHelper.GetString(s, "aftermath_ws");
            if (!string.IsNullOrEmpty(amVal) && !list.Contains(amVal))
            {
                list.Insert(0, amVal);
            }

            _aftermathCombo.Items.Clear();
            foreach (var o in list)
            {
                _aftermathCombo.Items.Add(o);
            }

            var amIdx = list.IndexOf(amVal);
            _aftermathCombo.SelectedIndex = amIdx >= 0 ? amIdx : (list.Count > 0 ? 0 : -1);
            _aftermathCombo.Enabled = SessionStateHelper.GetBool(s, "aftermath_enabled", false);
            _lblBlock.Text = SessionStateHelper.GetString(s, "block_reason");
            _lblSched.Text = SessionStateHelper.GetString(s, "scheduler_action");
            _lblSchedProv.Text = SessionStateHelper.GetString(s, "scheduler_provider");
            _lblTick.Text = SessionStateHelper.GetString(s, "scheduler_tick_seq");
            _lblWsDiag.Text = SessionStateHelper.GetString(s, "ws_diag");
            _ = eng;
        }
        finally
        {
            _suppressEvents = false;
        }
    }

    private void RenderAuxLists(JsonElement s)
    {
        RenderIgnoreList(s);
        RenderPartnerList(s);
        RenderTargetIgnoreList(s);
        RenderAddPriorityList(s);
    }

    private void ClearForm()
    {
        _suppressEvents = true;
        try
        {
            _pendingPfDistBySid.Clear();
            foreach (var key in HubUiConstants.BoolKeys)
            {
                if (_boolChecks.TryGetValue(key, out var cb))
                {
                    cb.Checked = false;
                }
            }

            _wsCombo.Items.Clear();
            _pullerCombo.Items.Clear();
            _fightLeaderCombo.Items.Clear();
            _partyFollowCombo.Items.Clear();
            _aftermathCombo.Items.Clear();
            _aftermathCombo.Enabled = false;
            _defProviderCombo.SelectedIndex = _defProviderCombo.Items.IndexOf("internal");
            if (_defProviderCombo.SelectedIndex < 0)
            {
                _defProviderCombo.SelectedIndex = 0;
            }

            _defCrit.Text = "35";
            _defMed.Text = "55";
            _defOverwrite.Text = "150";
            _defBuffs.Text = "";
            _lblBlock.Text = "";
            _lblSched.Text = "";
            _lblSchedProv.Text = "";
            _lblTick.Text = "";
            _lblWsDiag.Text = "";
            _lblFightLeaderOp.Text = "";
            _lblPartyFollowOp.Text = "";
            _pfFollowMinYalms.Text = "0.5";
            _pfFollowMaxYalms.Text = "50";
            _lblAddPriOp.Text = "";
            _lblPartnerOp.Text = "";
            _lblIgnoreInfo.Text = "";
            _lblIgnoreOp.Text = "";
            _lblTargetIgnOp.Text = "";
            _ignoreName.Text = "";
            _targetIgnName.Text = "";
            _addPriName.Text = "";
            _partnerName.Text = "";
            _abilityList.Items.Clear();
            _abilityPickCombo.Items.Clear();
            _ignoreList.Items.Clear();
            _partnerList.Items.Clear();
            _targetIgnList.Items.Clear();
            _addPriList.Items.Clear();
            _ignoreRows = [];
            _partnerRows = [];
            _targetIgnoreRows = [];
            _addPriorityRows = [];
            _selectedAbilities.Clear();
            _abilityOptions.Clear();
            _ignoreCurTarget.Enabled = false;
            _targetIgnCurTarget.Enabled = false;
            _addPriCurTarget.Enabled = false;
            _partnerCurTarget.Enabled = false;
            _pullerCombo.Enabled = false;
            _fightLeaderCombo.Enabled = false;
            _partyFollowCombo.Enabled = false;
            _pfFollowMinYalms.Enabled = false;
            _pfFollowMaxYalms.Enabled = false;
            UpdateBooleanCardVisuals();
        }
        finally
        {
            _suppressEvents = false;
        }
    }

    private void FillFromSession(string sid, JsonElement s)
    {
        if (sid != _lastFillSid)
        {
            _lastFillSid = sid;
            _ignoreRows = [];
            _partnerRows = [];
            _targetIgnoreRows = [];
            _addPriorityRows = [];
        }

        var eng = SessionStateHelper.GetString(s, "engine", "melee");
        var signature = SessionStateHelper.AbilitySignature(s);
        _abilitySignatureBySid[sid] = signature;

        var abilityOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("ability_options", out var ao) ? ao : default);
        var wsOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("weaponskill_options", out var wso) ? wso : default);
        var partnerOpts = new List<string> { "" };
        partnerOpts.AddRange(SessionStateHelper.SplitOptions(s.TryGetProperty("partner_options", out var po) ? po : default));

        _suppressEvents = true;
        try
        {
            if (!SequenceEqualOrdinal(_abilityOptions, abilityOpts))
            {
                _abilityOptions.Clear();
                _abilityOptions.AddRange(abilityOpts);
            }

            var nextSelected = ComputeSelectedAbilitiesFromState(s, _abilityOptions);
            if (!SequenceEqualOrdinal(_selectedAbilities, nextSelected))
            {
                _selectedAbilities.Clear();
                _selectedAbilities.AddRange(nextSelected);
                SyncAbilityListUi();
            }

            RefreshAbilityPickIfChanged();

            var wsDisplay = new List<string>(wsOpts);
            var wsRaw = SessionStateHelper.WsFromState(s, eng);
            if (!string.IsNullOrEmpty(wsRaw) && !wsDisplay.Contains(wsRaw))
            {
                wsDisplay.Insert(0, wsRaw);
            }

            _wsCombo.Items.Clear();
            foreach (var w in wsDisplay)
            {
                _wsCombo.Items.Add(w);
            }

            var wsIdx = wsDisplay.IndexOf(wsRaw);
            _wsCombo.SelectedIndex = wsIdx >= 0 ? wsIdx : (wsDisplay.Count > 0 ? 0 : -1);
            var amDisplay = new List<string>(wsOpts);
            var amRaw = SessionStateHelper.GetString(s, "aftermath_ws");
            if (!string.IsNullOrEmpty(amRaw) && !amDisplay.Contains(amRaw))
            {
                amDisplay.Insert(0, amRaw);
            }

            _aftermathCombo.Items.Clear();
            foreach (var w in amDisplay)
            {
                _aftermathCombo.Items.Add(w);
            }

            var amIdx = amDisplay.IndexOf(amRaw);
            _aftermathCombo.SelectedIndex = amIdx >= 0 ? amIdx : (amDisplay.Count > 0 ? 0 : -1);
            _aftermathCombo.Enabled = SessionStateHelper.GetBool(s, "aftermath_enabled", false);

            _pullerCombo.Items.Clear();
            foreach (var p in partnerOpts)
            {
                _pullerCombo.Items.Add(p);
            }

            var pullOn = SessionStateHelper.GetBool(s, "puller", false);
            var selPull = SessionStateHelper.GetString(s, "puller_selected");
            if (pullOn && !partnerOpts.Contains(selPull))
            {
                selPull = "";
            }

            _pullerCombo.SelectedIndex = Math.Max(0, partnerOpts.IndexOf(selPull));
            _pullerCombo.Enabled = pullOn;

            _fightLeaderCombo.Items.Clear();
            foreach (var p in partnerOpts)
            {
                _fightLeaderCombo.Items.Add(p);
            }

            var flOn = SessionStateHelper.GetBool(s, "fight_leader", false);
            var selFl = SessionStateHelper.GetString(s, "fight_leader_selected");
            if (flOn && !partnerOpts.Contains(selFl))
            {
                selFl = "";
            }

            _fightLeaderCombo.SelectedIndex = Math.Max(0, partnerOpts.IndexOf(selFl));
            _fightLeaderCombo.Enabled = flOn;

            _partyFollowCombo.Items.Clear();
            foreach (var p in partnerOpts)
            {
                _partyFollowCombo.Items.Add(p);
            }

            var pfOn = SessionStateHelper.GetBool(s, "party_follow", false);
            var selPf = SessionStateHelper.GetString(s, "party_follow_selected");
            if (pfOn && !partnerOpts.Contains(selPf))
            {
                selPf = "";
            }

            _partyFollowCombo.SelectedIndex = Math.Max(0, partnerOpts.IndexOf(selPf));
            _partyFollowCombo.Enabled = pfOn;

            _pfFollowMinYalms.Enabled = pfOn;
            _pfFollowMaxYalms.Enabled = pfOn;
            ApplyPartyFollowDistancesFromSnapshot(sid, s);

            var prov = SessionStateHelper.GetString(s, "defensive_provider", "internal");
            if (prov != "internal" && prov != "healbot")
            {
                prov = "internal";
            }

            _defProviderCombo.SelectedItem = prov;

            _defCrit.Text = SessionStateHelper.GetString(s, "defensive_critical_hpp", "35");
            _defMed.Text = SessionStateHelper.GetString(s, "defensive_medium_hpp", "55");
            _defOverwrite.Text = SessionStateHelper.GetString(s, "defensive_overwrite_interval", "150");
            _defBuffs.Text = SessionStateHelper.GetString(s, "defensive_buffs");

            _lblBlock.Text = SessionStateHelper.GetString(s, "block_reason");
            _lblSched.Text = SessionStateHelper.GetString(s, "scheduler_action");
            _lblSchedProv.Text = SessionStateHelper.GetString(s, "scheduler_provider");
            _lblTick.Text = SessionStateHelper.GetString(s, "scheduler_tick_seq");
            _lblWsDiag.Text = SessionStateHelper.GetString(s, "ws_diag");
            _lblFightLeaderOp.Text = SessionStateHelper.GetString(s, "fight_leader_last_op");
            _lblPartyFollowOp.Text = SessionStateHelper.GetString(s, "party_follow_last_op");
            _lblAddPriOp.Text = SessionStateHelper.GetString(s, "add_priority_last_op");
            _lblPartnerOp.Text = SessionStateHelper.GetString(s, "partner_last_op");
            _lblIgnoreOp.Text = SessionStateHelper.GetString(s, "ignore_last_op");
            _lblTargetIgnOp.Text = SessionStateHelper.GetString(s, "target_ignore_last_op");

            foreach (var key in HubUiConstants.BoolKeys)
            {
                if (!_boolChecks.TryGetValue(key, out var cb))
                {
                    continue;
                }

                if (_pendingBoolBySid.TryGetValue(sid, out var pend) && pend.TryGetValue(key, out var pr) && (DateTime.UtcNow - pr.ts).TotalSeconds < 3)
                {
                    cb.Checked = pr.val;
                }
                else
                {
                    cb.Checked = SessionStateHelper.GetBool(s, key, false);
                }
            }

            RenderAuxLists(s);
            UpdateBooleanCardVisuals();
        }
        finally
        {
            _suppressEvents = false;
        }
    }

    private void UpdateBooleanCardVisuals()
    {
        var healerOn = _boolChecks.TryGetValue("defensive_enabled", out var hb) && hb.Checked;
        _grpHealer.Text = healerOn ? "Healer / Defensive" : "Healer / Defensive (inactive)";
        var dim = SystemColors.GrayText;
        var bright = SystemColors.ControlText;
        foreach (var key in new[]
                 {
                     "defensive_cure_enabled",
                     "defensive_na_enabled",
                     "defensive_buff_enabled",
                     "defensive_overwrite_enabled",
                     "defensive_buff_self_only",
                 })
        {
            if (_boolChecks.TryGetValue(key, out var cb))
            {
                cb.ForeColor = healerOn ? bright : dim;
            }
        }
    }

    /// <summary>Rebuild the active-abilities list only when it differs from <see cref="_selectedAbilities"/> (avoids mirror-snapshot flicker).</summary>
    private void SyncAbilityListUi()
    {
        var cur = _abilityList.Items.Cast<object>().Select(x => x.ToString() ?? "").ToList();
        if (SequenceEqualOrdinal(cur, _selectedAbilities))
        {
            return;
        }

        var prev = _abilityList.SelectedIndex;
        var prevName = prev >= 0 && prev < cur.Count ? cur[prev] : null;
        _abilityList.BeginUpdate();
        try
        {
            _abilityList.Items.Clear();
            foreach (var a in _selectedAbilities)
            {
                _abilityList.Items.Add(a);
            }

            var selIdx = -1;
            if (prevName != null)
            {
                for (var i = 0; i < _selectedAbilities.Count; i++)
                {
                    if (string.Equals(_selectedAbilities[i], prevName, StringComparison.Ordinal))
                    {
                        selIdx = i;
                        break;
                    }
                }
            }

            if (selIdx >= 0)
            {
                _abilityList.SelectedIndex = selIdx;
            }
            else if (prev >= 0 && prev < _abilityList.Items.Count)
            {
                _abilityList.SelectedIndex = prev;
            }
        }
        finally
        {
            _abilityList.EndUpdate();
        }
    }

    private void RefreshAbilityPickIfChanged()
    {
        var avail = _abilityOptions.Where(a => !_selectedAbilities.Any(s => string.Equals(s, a, StringComparison.Ordinal))).ToList();
        var cur = _abilityPickCombo.Items.Cast<object>().Select(x => x.ToString() ?? "").ToList();
        if (SequenceEqualOrdinal(cur, avail))
        {
            return;
        }

        var prevPick = _abilityPickCombo.SelectedItem?.ToString();
        _abilityPickCombo.Items.Clear();
        foreach (var a in avail)
        {
            _abilityPickCombo.Items.Add(a);
        }

        var idx = string.IsNullOrEmpty(prevPick) ? -1 : avail.FindIndex(x => string.Equals(x, prevPick, StringComparison.Ordinal));
        _abilityPickCombo.SelectedIndex = idx >= 0 ? idx : (avail.Count > 0 ? 0 : -1);
    }

    private void RenderIgnoreList(JsonElement s)
    {
        var newRows = SessionStateHelper.ParseIgnoreEntriesFrom(s, "ignore_entries");
        var itid = 0;
        if (s.TryGetProperty("ignore_target_id", out var tid) && tid.ValueKind == JsonValueKind.Number)
        {
            itid = tid.GetInt32();
        }

        var tname = SessionStateHelper.GetString(s, "ignore_target_name");
        _lblIgnoreInfo.Text = itid > 0 ? $"Current target: {tname} (id {itid})" : "Current target: (none)";
        var tgtOk = itid > 0;
        _ignoreCurTarget.Enabled = tgtOk;
        _targetIgnCurTarget.Enabled = tgtOk;
        _addPriCurTarget.Enabled = tgtOk;

        if (newRows.SequenceEqual(_ignoreRows) && _ignoreList.Items.Count == newRows.Count)
        {
            return;
        }

        int? preserved = null;
        if (_ignoreList.SelectedIndex >= 0 && _ignoreRows.Count > 0 && _ignoreList.SelectedIndex < _ignoreRows.Count)
        {
            preserved = _ignoreRows[_ignoreList.SelectedIndex].Id;
        }

        _ignoreRows = newRows;
        _ignoreList.Items.Clear();
        foreach (var (id, name) in _ignoreRows)
        {
            _ignoreList.Items.Add($"{name} [{id}]");
        }

        if (preserved is { } pid)
        {
            for (var i = 0; i < _ignoreRows.Count; i++)
            {
                if (_ignoreRows[i].Id == pid)
                {
                    _ignoreList.SelectedIndex = i;
                    break;
                }
            }
        }
    }

    private void RenderPartnerList(JsonElement s)
    {
        var newRows = SessionStateHelper.ParseIgnoreEntriesFrom(s, "partner_entries");
        var itid = 0;
        if (s.TryGetProperty("ignore_target_id", out var tid) && tid.ValueKind == JsonValueKind.Number)
        {
            itid = tid.GetInt32();
        }

        _partnerCurTarget.Enabled = itid > 0;
        if (newRows.SequenceEqual(_partnerRows) && _partnerList.Items.Count == newRows.Count)
        {
            return;
        }

        int? preserved = null;
        if (_partnerList.SelectedIndex >= 0 && _partnerRows.Count > 0 && _partnerList.SelectedIndex < _partnerRows.Count)
        {
            preserved = _partnerRows[_partnerList.SelectedIndex].Id;
        }

        _partnerRows = newRows;
        _partnerList.Items.Clear();
        foreach (var (id, name) in _partnerRows)
        {
            _partnerList.Items.Add($"{name} [{id}]");
        }

        if (preserved is { } pid)
        {
            for (var i = 0; i < _partnerRows.Count; i++)
            {
                if (_partnerRows[i].Id == pid)
                {
                    _partnerList.SelectedIndex = i;
                    break;
                }
            }
        }
    }

    private void RenderTargetIgnoreList(JsonElement s)
    {
        var newRows = SessionStateHelper.ParseIgnoreEntriesFrom(s, "target_ignore_entries");
        if (newRows.SequenceEqual(_targetIgnoreRows) && _targetIgnList.Items.Count == newRows.Count)
        {
            return;
        }

        int? preserved = null;
        if (_targetIgnList.SelectedIndex >= 0 && _targetIgnoreRows.Count > 0 && _targetIgnList.SelectedIndex < _targetIgnoreRows.Count)
        {
            preserved = _targetIgnoreRows[_targetIgnList.SelectedIndex].Slot;
        }

        _targetIgnoreRows = newRows;
        _targetIgnList.Items.Clear();
        foreach (var (slot, name) in _targetIgnoreRows)
        {
            _targetIgnList.Items.Add($"{name} [{slot}]");
        }

        if (preserved is { } ps)
        {
            for (var i = 0; i < _targetIgnoreRows.Count; i++)
            {
                if (_targetIgnoreRows[i].Slot == ps)
                {
                    _targetIgnList.SelectedIndex = i;
                    break;
                }
            }
        }
    }

    private void RenderAddPriorityList(JsonElement s)
    {
        var newRows = SessionStateHelper.ParseIgnoreEntriesFrom(s, "add_priority_entries");
        if (newRows.SequenceEqual(_addPriorityRows) && _addPriList.Items.Count == newRows.Count)
        {
            return;
        }

        string? preserved = null;
        if (_addPriList.SelectedIndex >= 0 && _addPriorityRows.Count > 0 && _addPriList.SelectedIndex < _addPriorityRows.Count)
        {
            preserved = _addPriorityRows[_addPriList.SelectedIndex].Name;
        }

        _addPriorityRows = newRows;
        _addPriList.Items.Clear();
        foreach (var (slot, name) in _addPriorityRows)
        {
            _addPriList.Items.Add($"{name} [{slot}]");
        }

        if (preserved != null)
        {
            for (var i = 0; i < _addPriorityRows.Count; i++)
            {
                if (_addPriorityRows[i].Name == preserved)
                {
                    _addPriList.SelectedIndex = i;
                    break;
                }
            }
        }
    }

    private void OnAnyBool(string key, bool val)
    {
        if (_suppressEvents)
        {
            return;
        }

        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        if (_snapshotDoc is null || !_snapshotDoc.RootElement.TryGetProperty("sessions", out var sessions) || !sessions.TryGetProperty(sid, out var s))
        {
            return;
        }

        if (key == "Start_Engine")
        {
            Forward(sid, val ? new Dictionary<string, object?> { ["op"] = "start_engine" } : new Dictionary<string, object?> { ["op"] = "stop_engine" });
        }
        else
        {
            Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = key, ["value"] = val ? "on" : "off" });
        }

        if (!_pendingBoolBySid.TryGetValue(sid, out var pend))
        {
            pend = [];
            _pendingBoolBySid[sid] = pend;
        }

        pend[key] = (val, DateTime.UtcNow);
        UpdateBooleanCardVisuals();

        if (key == "puller")
        {
            _pullerCombo.Enabled = val;
            if (val && _pullerCombo.SelectedItem is string ps && !string.IsNullOrEmpty(ps) && !_pullerCombo.Items.Cast<object>().Any(x => Equals(x.ToString(), ps)))
            {
                _pullerCombo.SelectedIndex = 0;
                OnPullerSelected();
            }
        }

        if (key == "fight_leader")
        {
            _fightLeaderCombo.Enabled = val;
            if (val && _fightLeaderCombo.SelectedItem is string fs && !string.IsNullOrEmpty(fs) && !_fightLeaderCombo.Items.Cast<object>().Any(x => Equals(x.ToString(), fs)))
            {
                _fightLeaderCombo.SelectedIndex = 0;
                OnFightLeaderSelected();
            }
        }

        if (key == "party_follow")
        {
            _partyFollowCombo.Enabled = val;
            _pfFollowMinYalms.Enabled = val;
            _pfFollowMaxYalms.Enabled = val;
            if (val && _partyFollowCombo.SelectedItem is string pfs && !string.IsNullOrEmpty(pfs) &&
                !_partyFollowCombo.Items.Cast<object>().Any(x => Equals(x.ToString(), pfs)))
            {
                _partyFollowCombo.SelectedIndex = 0;
                OnPartyFollowSelected();
            }
        }
        else if (key == "aftermath_enabled")
        {
            _aftermathCombo.Enabled = val;
        }

        _ = s;
    }

    private void OnWsSelected()
    {
        if (_suppressEvents)
        {
            return;
        }

        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        if (_snapshotDoc is null || !_snapshotDoc.RootElement.TryGetProperty("sessions", out var sessions) || !sessions.TryGetProperty(sid, out var s))
        {
            return;
        }

        var eng = SessionStateHelper.GetString(s, "engine", "melee");
        var val = _wsCombo.SelectedItem?.ToString() ?? "";
        SendWsUpdate(sid, eng, val);
    }

    private void SendWsUpdate(string sid, string eng, string val)
    {
        var path = eng == "melee" ? "ws1" : "weaponskill";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = path, ["value"] = val });
        _pendingWsBySid[sid] = (val, DateTime.UtcNow);
    }

    private void OnAftermathWsSelected()
    {
        if (_suppressEvents)
        {
            return;
        }

        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var val = _aftermathCombo.SelectedItem?.ToString() ?? "";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "aftermath_ws", ["value"] = val });
    }

    private void OnPullerSelected()
    {
        if (_suppressEvents)
        {
            return;
        }

        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var name = _pullerCombo.SelectedItem?.ToString() ?? "";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_partner", ["slot"] = "puller", ["name"] = name });
    }

    private void OnFightLeaderSelected()
    {
        if (_suppressEvents)
        {
            return;
        }

        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var name = _fightLeaderCombo.SelectedItem?.ToString() ?? "";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_fight_leader", ["name"] = name });
    }

    private void OnPartyFollowSelected()
    {
        if (_suppressEvents)
        {
            return;
        }

        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var name = _partyFollowCombo.SelectedItem?.ToString() ?? "";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_party_follow", ["name"] = name });
    }

    private void OnPartyFollowDistanceChanged()
    {
        if (_suppressEvents)
        {
            return;
        }

        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        PushPartyFollowDistances(sid);
    }

    private void PushPartyFollowDistances(string sid)
    {
        var minRaw = (_pfFollowMinYalms.Text ?? "").Trim();
        var maxRaw = (_pfFollowMaxYalms.Text ?? "").Trim();
        if (!double.TryParse(minRaw, NumberStyles.Float, CultureInfo.InvariantCulture, out var minY))
        {
            minY = 0.5;
        }

        if (!double.TryParse(maxRaw, NumberStyles.Float, CultureInfo.InvariantCulture, out var maxY))
        {
            maxY = 50;
        }

        minY = Math.Clamp(minY, 0.01, 99.0);
        maxY = Math.Clamp(maxY, 0.1, 200.0);
        if (minY >= maxY)
        {
            maxY = Math.Min(200.0, minY + 0.01);
        }

        if (minY >= maxY)
        {
            minY = 0.5;
            maxY = 50;
        }

        var minS = minY.ToString("0.###", CultureInfo.InvariantCulture);
        var maxS = maxY.ToString("0.###", CultureInfo.InvariantCulture);
        _pfFollowMinYalms.Text = minS;
        _pfFollowMaxYalms.Text = maxS;
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "party_follow_min", ["value"] = minS });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "party_follow_max", ["value"] = maxS });
        _pendingPfDistBySid[sid] = (minS, maxS, DateTime.UtcNow);
    }

    private static bool PartyFollowDistPairEcho(string srvMin, string srvMax, string pendMin, string pendMax)
    {
        if (!double.TryParse(srvMin.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var a))
        {
            return false;
        }

        if (!double.TryParse(srvMax.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var b))
        {
            return false;
        }

        if (!double.TryParse(pendMin.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var c))
        {
            return false;
        }

        if (!double.TryParse(pendMax.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var d))
        {
            return false;
        }

        return Math.Abs(a - c) < 1e-9 && Math.Abs(b - d) < 1e-9;
    }

    private void ApplyPartyFollowDistancesFromSnapshot(string sid, JsonElement s)
    {
        var minSrv = SessionStateHelper.GetString(s, "party_follow_min", "0.5");
        var maxSrv = SessionStateHelper.GetString(s, "party_follow_max", "50");

        if (_pfFollowMinYalms.Focused || _pfFollowMaxYalms.Focused)
        {
            return;
        }

        if (_pendingPfDistBySid.TryGetValue(sid, out var pfd))
        {
            var ageSec = (DateTime.UtcNow - pfd.ts).TotalSeconds;
            if (PartyFollowDistPairEcho(minSrv, maxSrv, pfd.min, pfd.max))
            {
                _pendingPfDistBySid.Remove(sid);
            }
            else if (ageSec < 3.0)
            {
                return;
            }
            else
            {
                _pendingPfDistBySid.Remove(sid);
            }
        }

        if (!string.Equals(_pfFollowMinYalms.Text, minSrv, StringComparison.Ordinal))
        {
            _pfFollowMinYalms.Text = minSrv;
        }

        if (!string.Equals(_pfFollowMaxYalms.Text, maxSrv, StringComparison.Ordinal))
        {
            _pfFollowMaxYalms.Text = maxSrv;
        }
    }

    private void OnDefProviderSelected()
    {
        if (_suppressEvents)
        {
            return;
        }

        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var prov = (_defProviderCombo.SelectedItem as string) ?? "internal";
        if (prov != "internal" && prov != "healbot")
        {
            prov = "internal";
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_provider", ["value"] = prov });
    }

    private void OnDefThresholdChanged()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        int crit = 35, med = 55, overwrite = 150;
        try
        {
            crit = (int)Math.Clamp(int.Parse(_defCrit.Text.Trim()), 1, 99);
        }
        catch
        {
            /* keep default */
        }

        try
        {
            med = (int)Math.Clamp(int.Parse(_defMed.Text.Trim()), 1, 99);
        }
        catch
        {
            /* keep default */
        }

        try
        {
            overwrite = (int)Math.Clamp(int.Parse(_defOverwrite.Text.Trim()), 10, 1800);
        }
        catch
        {
            /* keep default */
        }

        if (med < crit)
        {
            med = crit;
        }

        var buffsRaw = _defBuffs.Text ?? "";
        var buffsClean = string.Join(
            "|",
            buffsRaw.Replace(',', '|').Split('|').Select(x => x.Trim()).Where(x => x.Length > 0)
        );
        _defCrit.Text = crit.ToString();
        _defMed.Text = med.ToString();
        _defOverwrite.Text = overwrite.ToString();
        _defBuffs.Text = buffsClean;
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_critical_hpp", ["value"] = crit });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_medium_hpp", ["value"] = med });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_overwrite_interval", ["value"] = overwrite });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_buffs", ["value"] = buffsClean });
    }

    private void SendAbilitiesUpdate()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_abilities", ["value"] = string.Join("|", _selectedAbilities) });
    }

    private void AddAbility()
    {
        _abilityInteractionUtc = DateTime.UtcNow;
        if (_abilityPickCombo.SelectedItem is not string name || string.IsNullOrEmpty(name))
        {
            return;
        }

        if (!_selectedAbilities.Contains(name))
        {
            _selectedAbilities.Add(name);
            SyncAbilityListUi();
            RefreshAbilityPickIfChanged();
            SendAbilitiesUpdate();
        }
    }

    private void RemoveAbility()
    {
        _abilityInteractionUtc = DateTime.UtcNow;
        var idx = _abilityList.SelectedIndex;
        if (idx < 0 || idx >= _selectedAbilities.Count)
        {
            return;
        }

        _selectedAbilities.RemoveAt(idx);
        SyncAbilityListUi();
        RefreshAbilityPickIfChanged();
        SendAbilitiesUpdate();
    }

    private void MoveAbilityUp()
    {
        _abilityInteractionUtc = DateTime.UtcNow;
        var idx = _abilityList.SelectedIndex;
        if (idx <= 0)
        {
            return;
        }

        (_selectedAbilities[idx - 1], _selectedAbilities[idx]) = (_selectedAbilities[idx], _selectedAbilities[idx - 1]);
        SyncAbilityListUi();
        _abilityList.SelectedIndex = idx - 1;
        SendAbilitiesUpdate();
    }

    private void MoveAbilityDown()
    {
        _abilityInteractionUtc = DateTime.UtcNow;
        var idx = _abilityList.SelectedIndex;
        if (idx < 0 || idx >= _selectedAbilities.Count - 1)
        {
            return;
        }

        (_selectedAbilities[idx + 1], _selectedAbilities[idx]) = (_selectedAbilities[idx], _selectedAbilities[idx + 1]);
        SyncAbilityListUi();
        _abilityList.SelectedIndex = idx + 1;
        SendAbilitiesUpdate();
    }

    private void IgnoreAddByName()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var name = _ignoreName.Text.Trim();
        if (name.Length == 0)
        {
            return;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "ignore_add", ["name"] = name });
    }

    private void IgnoreAddCurrent()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "ignore_add_current" });
    }

    private void IgnoreRemove()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var idx = _ignoreList.SelectedIndex;
        if (idx < 0)
        {
            return;
        }

        var tid = idx < _ignoreRows.Count ? _ignoreRows[idx].Id : SessionStateHelper.ParseTrailingBracketId(_ignoreList.Items[idx]?.ToString() ?? "");
        if (tid is null or 0)
        {
            return;
        }

        Forward(
            sid,
            new Dictionary<string, object?> { ["op"] = "ignore_remove", ["mob_id"] = tid.Value, ["id"] = tid.Value }
        );
    }

    private void PartnerAddByName()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var name = _partnerName.Text.Trim();
        if (name.Length == 0)
        {
            return;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "partner_add", ["name"] = name });
    }

    private void PartnerAddCurrent()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "partner_add_current" });
    }

    private void PartnerRemove()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var idx = _partnerList.SelectedIndex;
        if (idx < 0)
        {
            return;
        }

        var tid = idx < _partnerRows.Count ? _partnerRows[idx].Id : SessionStateHelper.ParseTrailingBracketId(_partnerList.Items[idx]?.ToString() ?? "");
        if (tid is null or 0)
        {
            return;
        }

        Forward(
            sid,
            new Dictionary<string, object?> { ["op"] = "partner_remove", ["mob_id"] = tid.Value, ["id"] = tid.Value }
        );
    }

    private void TargetIgnAddByName()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var name = _targetIgnName.Text.Trim();
        if (name.Length == 0)
        {
            return;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "target_ignore_add", ["name"] = name });
    }

    private void TargetIgnAddCurrent()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "target_ignore_add_current" });
    }

    private void TargetIgnRemove()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var idx = _targetIgnList.SelectedIndex;
        if (idx < 0)
        {
            return;
        }

        var slot = idx < _targetIgnoreRows.Count ? _targetIgnoreRows[idx].Slot : SessionStateHelper.ParseTrailingBracketId(_targetIgnList.Items[idx]?.ToString() ?? "");
        if (!slot.HasValue || slot.Value < 1)
        {
            return;
        }

        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "target_ignore_remove",
                ["index"] = slot.Value,
                ["slot"] = slot.Value,
            }
        );
    }

    private void AddPriorityByName()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var name = _addPriName.Text.Trim();
        if (name.Length == 0)
        {
            return;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "add_priority_add", ["name"] = name });
    }

    private void AddPriorityCurrent()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "add_priority_add_current" });
    }

    private void AddPriorityRemove()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var idx = _addPriList.SelectedIndex;
        if (idx < 0)
        {
            return;
        }

        var slot = idx < _addPriorityRows.Count ? _addPriorityRows[idx].Slot : SessionStateHelper.ParseTrailingBracketId(_addPriList.Items[idx]?.ToString() ?? "");
        if (!slot.HasValue || slot.Value < 1)
        {
            return;
        }

        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "add_priority_remove",
                ["index"] = slot.Value,
                ["slot"] = slot.Value,
            }
        );
    }

    private void AddPriorityMove(string direction)
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var idx = _addPriList.SelectedIndex;
        if (idx < 0)
        {
            return;
        }

        var slot = idx < _addPriorityRows.Count ? _addPriorityRows[idx].Slot : SessionStateHelper.ParseTrailingBracketId(_addPriList.Items[idx]?.ToString() ?? "");
        if (!slot.HasValue || slot.Value < 1)
        {
            return;
        }

        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "add_priority_move",
                ["index"] = slot.Value,
                ["slot"] = slot.Value,
                ["direction"] = direction,
            }
        );
    }

    private async void SaveRemote()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        PushFullFormState(sid);
        await Task.Delay(200).ConfigureAwait(true);
        if (!IsDisposed)
        {
            Forward(sid, new Dictionary<string, object?> { ["op"] = "save" });
        }
    }

    private void ToggleEngine()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        if (_snapshotDoc is null || !_snapshotDoc.RootElement.TryGetProperty("sessions", out var sessions) || !sessions.TryGetProperty(sid, out var s))
        {
            return;
        }

        var running = SessionStateHelper.GetBool(s, "Start_Engine", false);
        if (running)
        {
            Forward(sid, new Dictionary<string, object?> { ["op"] = "stop_engine" });
        }
        else
        {
            Forward(sid, new Dictionary<string, object?> { ["op"] = "start_engine" });
        }
    }

    private void PushFullFormState(string sid)
    {
        if (_snapshotDoc is null || !_snapshotDoc.RootElement.TryGetProperty("sessions", out var sessions) || !sessions.TryGetProperty(sid, out var s))
        {
            return;
        }

        var eng = SessionStateHelper.GetString(s, "engine", "melee");
        var wsVal = _wsCombo.SelectedItem?.ToString() ?? "";
        SendWsUpdate(sid, eng, wsVal);
        SendAbilitiesUpdate();
        foreach (var key in HubUiConstants.BoolKeys)
        {
            var val = _boolChecks.TryGetValue(key, out var cb) && cb.Checked;
            if (key == "Start_Engine")
            {
                Forward(sid, val ? new Dictionary<string, object?> { ["op"] = "start_engine" } : new Dictionary<string, object?> { ["op"] = "stop_engine" });
            }
            else
            {
                Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = key, ["value"] = val ? "on" : "off" });
            }

            if (!_pendingBoolBySid.TryGetValue(sid, out var pend))
            {
                pend = [];
                _pendingBoolBySid[sid] = pend;
            }

            pend[key] = (val, DateTime.UtcNow);
        }

        var prov = (_defProviderCombo.SelectedItem as string) ?? "internal";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_provider", ["value"] = prov });
        OnDefThresholdChanged();
        var pull = _pullerCombo.SelectedItem?.ToString() ?? "";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_partner", ["slot"] = "puller", ["name"] = pull });
        var fl = _fightLeaderCombo.SelectedItem?.ToString() ?? "";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_fight_leader", ["name"] = fl });
        var pf = _partyFollowCombo.SelectedItem?.ToString() ?? "";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_party_follow", ["name"] = pf });
        PushPartyFollowDistances(sid);
        UpdateBooleanCardVisuals();
    }
}
