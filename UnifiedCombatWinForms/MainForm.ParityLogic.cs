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
        if (string.IsNullOrEmpty(_selectedSid))
        {
            ClearForm();
            return;
        }
        if (!TryLoadWorkingProfileForSid(_selectedSid, out var profileDoc)
            && !TryLoadProfileForSid(_selectedSid, out profileDoc))
        {
            ClearForm();
            return;
        }

        using (profileDoc)
        {
            FillFromSession(_selectedSid, profileDoc.RootElement);
        }

        PushFullFormState(_selectedSid);
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
        RenderPathHunterList(s);
    }

    private void ClearForm()
    {
        _suppressEvents = true;
        try
        {
            _pendingPfDistBySid.Clear();
            _pendingSpacingBySid.Clear();
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
            _pfFollowMinYalms.Text = "0.5";
            _pfFollowMaxYalms.Text = "50";
            _pfFightFollowMinYalms.Text = "3";
            _pfFightFollowHoldS.Text = "8";
            _spUsePrediction.Checked = true;
            _spBandMin.Text = "-0.9";
            _spBandMax.Text = "0.4";
            _spModelSizeFloor.Text = "0.9";
            _spLookahead.Text = "0.25";
            _spAnchorInvalidTicks.Text = "5";
            _spEmergencyMargin.Text = "0.1";
            _spSwitchPenalty.Text = "0.75";
            _spSwitchMargin.Text = "0.35";
            _spArrivalTolerance.Text = "0.2";
            _spMaxAgents.Text = "6";
            _pathFileValue.Text = "";
            _pathRouteTypeValue.Text = "unknown";
            _pathDistanceValue.Text = "0.0";
            _pathPointCountValue.Text = "0";
            _pathPartyGateYalms.Text = "3";
            _pathResumeIndexWindow.Text = "12";
            _pathHunterMaxZDelta.Text = "2";
            _pathHunterMaxTargetRange.Text = "20";
            _pathHunterClaimTimeout.Text = "4";
            _pathHunterIgnoreCooldown.Text = "20";
            _pathPullActionType.SelectedItem = "ja";
            _pathPullActionName.Items.Clear();
            _pathPullJaOptions.Clear();
            _pathPullSpellOptions.Clear();
            _pathHunterList.Items.Clear();
            _pathHunterRows = [];
            _tankEnmityList.Items.Clear();
            _tankEnmityRows = [];
            _tankEnmityTypeCombo.SelectedItem = "ja";
            _tankEnmityNameCombo.Items.Clear();
            _tankEnmityNameCombo.Text = "";
            _pathHunterName.Text = "";
            _corRoll1Combo.Items.Clear();
            _corRoll2Combo.Items.Clear();
            _corRoll1Combo.Enabled = false;
            _corRoll2Combo.Enabled = false;
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
            _pfFightFollowMinYalms.Enabled = false;
            _pfFightFollowHoldS.Enabled = false;
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
        var pullJaOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("path_pull_ja_options", out var pjo) ? pjo : default);
        var pullSpellOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("path_pull_spell_options", out var pso) ? pso : default);
        var tankEnmityActions = SessionStateHelper.SplitOptions(s.TryGetProperty("tank_enmity_actions", out var tea) ? tea : default);
        var partnerOpts = new List<string> { "" };
        partnerOpts.AddRange(SessionStateHelper.SplitOptions(s.TryGetProperty("partner_options", out var po) ? po : default));
        var pullerOpts = new List<string> { "" };
        pullerOpts.AddRange(SessionStateHelper.SplitOptions(s.TryGetProperty("puller_options", out var plo) ? plo : default));
        if (pullerOpts.Count <= 1)
        {
            pullerOpts.Clear();
            pullerOpts.AddRange(partnerOpts);
        }

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
            foreach (var p in pullerOpts)
            {
                _pullerCombo.Items.Add(p);
            }

            var pullOn = SessionStateHelper.GetBool(s, "puller", false);
            var selPull = SessionStateHelper.GetString(s, "puller_selected");
            if (pullOn && !pullerOpts.Contains(selPull))
            {
                selPull = "";
            }

            _pullerCombo.SelectedIndex = Math.Max(0, pullerOpts.IndexOf(selPull));
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
            _pfFightFollowMinYalms.Enabled = pfOn;
            _pfFightFollowHoldS.Enabled = pfOn;
            ApplyPartyFollowDistancesFromSnapshot(sid, s);
            ApplySpacingTuningFromSnapshot(sid, s);

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

            _pathFileValue.Text = SessionStateHelper.GetString(s, "path_file_name");
            _pathRouteTypeValue.Text = SessionStateHelper.GetString(s, "path_route_type", "unknown");
            var pDist = SessionStateHelper.GetString(s, "path_distance_to_start", "0");
            if (!double.TryParse(pDist, NumberStyles.Float, CultureInfo.InvariantCulture, out var pDistN))
            {
                pDistN = 0;
            }
            _pathDistanceValue.Text = pDistN.ToString("0.00", CultureInfo.InvariantCulture);
            _pathPointCountValue.Text = SessionStateHelper.GetString(s, "path_points_count", "0");
            var gateIncoming = SessionStateHelper.GetString(s, "path_party_gate_yalms", "3");
            if (!_pathPartyGateYalms.Focused && !EquivalentNumericText(_pathPartyGateYalms.Text ?? "", gateIncoming))
            {
                _pathPartyGateYalms.Text = gateIncoming;
            }
            var resumeWindowIncoming = SessionStateHelper.GetString(s, "path_resume_index_window", "12");
            if (!_pathResumeIndexWindow.Focused && !EquivalentNumericText(_pathResumeIndexWindow.Text ?? "", resumeWindowIncoming))
            {
                _pathResumeIndexWindow.Text = resumeWindowIncoming;
            }
            var zGateIncoming = SessionStateHelper.GetString(s, "path_hunter_max_z_delta", "2");
            if (!_pathHunterMaxZDelta.Focused && !EquivalentNumericText(_pathHunterMaxZDelta.Text ?? "", zGateIncoming))
            {
                _pathHunterMaxZDelta.Text = zGateIncoming;
            }
            var rangeIncoming = SessionStateHelper.GetString(s, "path_hunter_max_target_range", "20");
            if (!_pathHunterMaxTargetRange.Focused && !EquivalentNumericText(_pathHunterMaxTargetRange.Text ?? "", rangeIncoming))
            {
                _pathHunterMaxTargetRange.Text = rangeIncoming;
            }
            var claimTimeoutIncoming = SessionStateHelper.GetString(s, "path_hunter_claim_timeout_s", "4");
            if (!_pathHunterClaimTimeout.Focused && !EquivalentNumericText(_pathHunterClaimTimeout.Text ?? "", claimTimeoutIncoming))
            {
                _pathHunterClaimTimeout.Text = claimTimeoutIncoming;
            }
            var ignoreCooldownIncoming = SessionStateHelper.GetString(s, "path_hunter_ignore_cooldown_s", "20");
            if (!_pathHunterIgnoreCooldown.Focused && !EquivalentNumericText(_pathHunterIgnoreCooldown.Text ?? "", ignoreCooldownIncoming))
            {
                _pathHunterIgnoreCooldown.Text = ignoreCooldownIncoming;
            }
            if (!SequenceEqualOrdinal(_pathPullJaOptions, pullJaOpts))
            {
                _pathPullJaOptions.Clear();
                _pathPullJaOptions.AddRange(pullJaOpts);
            }
            if (!SequenceEqualOrdinal(_pathPullSpellOptions, pullSpellOpts))
            {
                _pathPullSpellOptions.Clear();
                _pathPullSpellOptions.AddRange(pullSpellOpts);
            }
            if (!SequenceEqualOrdinal(_tankEnmityRows, tankEnmityActions))
            {
                _tankEnmityRows = tankEnmityActions.Where(x => !string.IsNullOrWhiteSpace(x)).ToList();
                RebindTankEnmityListUi();
            }
            var pullTypeIncoming = SessionStateHelper.GetString(s, "path_pull_action_type", "ja");
            if (!string.Equals(pullTypeIncoming, "spell", StringComparison.OrdinalIgnoreCase))
            {
                pullTypeIncoming = "ja";
            }
            if (!_pathPullActionType.DroppedDown && !string.Equals(_pathPullActionType.SelectedItem?.ToString() ?? "", pullTypeIncoming, StringComparison.Ordinal))
            {
                _pathPullActionType.SelectedItem = pullTypeIncoming;
            }
            var pullNameIncoming = SessionStateHelper.GetString(s, "path_pull_action_name");
            if (!_pathPullActionName.DroppedDown)
            {
                RefreshPathPullActionNameOptions(pullTypeIncoming, pullNameIncoming);
            }
            if (_tankEnmityTypeCombo.SelectedItem is not string tenType || (tenType != "ja" && tenType != "spell"))
            {
                _tankEnmityTypeCombo.SelectedItem = "ja";
            }
            RefreshTankEnmityNameOptions((_tankEnmityTypeCombo.SelectedItem?.ToString() ?? "ja"), _tankEnmityNameCombo.Text ?? "");
            RenderPathHunterList(s);
            ApplyCorRollFromSnapshot(_corRoll1Combo, SessionStateHelper.GetString(s, "cor_roll_1"));
            ApplyCorRollFromSnapshot(_corRoll2Combo, SessionStateHelper.GetString(s, "cor_roll_2"));
            _corRoll1Combo.Enabled = true;
            _corRoll2Combo.Enabled = true;

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

    private void ApplyOptionsFromSnapshotIfPresent(string sid, JsonElement s)
    {
        var hasAbility = s.TryGetProperty("ability_options", out var ao) && ao.ValueKind == JsonValueKind.String;
        var hasWs = s.TryGetProperty("weaponskill_options", out var wso) && wso.ValueKind == JsonValueKind.String;
        var hasPullJa = s.TryGetProperty("path_pull_ja_options", out var pjo) && pjo.ValueKind == JsonValueKind.String;
        var hasPullSpell = s.TryGetProperty("path_pull_spell_options", out var pso) && pso.ValueKind == JsonValueKind.String;
        if (!hasAbility && !hasWs && !hasPullJa && !hasPullSpell)
        {
            return;
        }

        var abilityOpts = SessionStateHelper.SplitOptions(hasAbility ? ao : default);
        var wsOpts = SessionStateHelper.SplitOptions(hasWs ? wso : default);
        var pullJaOpts = SessionStateHelper.SplitOptions(hasPullJa ? pjo : default);
        var pullSpellOpts = SessionStateHelper.SplitOptions(hasPullSpell ? pso : default);
        var changed = false;

        _suppressEvents = true;
        try
        {
            if (hasAbility && !SequenceEqualOrdinal(_abilityOptions, abilityOpts))
            {
                _abilityOptions.Clear();
                _abilityOptions.AddRange(abilityOpts);
                RefreshAbilityPickIfChanged();
                changed = true;
            }

            if (hasWs)
            {
                var wsText = (_wsCombo.Text ?? "").Trim();
                var wsDisplay = new List<string>(wsOpts);
                if (!string.IsNullOrEmpty(wsText) && !wsDisplay.Contains(wsText))
                {
                    wsDisplay.Insert(0, wsText);
                }

                var currentWs = _wsCombo.Items.Cast<object>().Select(x => x.ToString() ?? "").ToList();
                if (!SequenceEqualOrdinal(currentWs, wsDisplay))
                {
                    _wsCombo.Items.Clear();
                    foreach (var w in wsDisplay)
                    {
                        _wsCombo.Items.Add(w);
                    }
                    changed = true;
                }
                var wsIdx = wsDisplay.FindIndex(x => string.Equals(x, wsText, StringComparison.Ordinal));
                _wsCombo.SelectedIndex = wsIdx >= 0 ? wsIdx : (wsDisplay.Count > 0 ? 0 : -1);

                var amText = (_aftermathCombo.Text ?? "").Trim();
                var amDisplay = new List<string>(wsOpts);
                if (!string.IsNullOrEmpty(amText) && !amDisplay.Contains(amText))
                {
                    amDisplay.Insert(0, amText);
                }
                var currentAm = _aftermathCombo.Items.Cast<object>().Select(x => x.ToString() ?? "").ToList();
                if (!SequenceEqualOrdinal(currentAm, amDisplay))
                {
                    _aftermathCombo.Items.Clear();
                    foreach (var w in amDisplay)
                    {
                        _aftermathCombo.Items.Add(w);
                    }
                    changed = true;
                }
                var amIdx = amDisplay.FindIndex(x => string.Equals(x, amText, StringComparison.Ordinal));
                _aftermathCombo.SelectedIndex = amIdx >= 0 ? amIdx : (amDisplay.Count > 0 ? 0 : -1);
            }

            if (hasPullJa && !SequenceEqualOrdinal(_pathPullJaOptions, pullJaOpts))
            {
                _pathPullJaOptions.Clear();
                _pathPullJaOptions.AddRange(pullJaOpts);
                changed = true;
            }
            if (hasPullSpell && !SequenceEqualOrdinal(_pathPullSpellOptions, pullSpellOpts))
            {
                _pathPullSpellOptions.Clear();
                _pathPullSpellOptions.AddRange(pullSpellOpts);
                changed = true;
            }
            if (hasPullJa || hasPullSpell)
            {
                var pullType = (_pathPullActionType.SelectedItem?.ToString() ?? "ja").ToLowerInvariant();
                var pullName = (_pathPullActionName.Text ?? "").Trim();
                RefreshPathPullActionNameOptions(pullType, pullName);
                var tankType = (_tankEnmityTypeCombo.SelectedItem?.ToString() ?? "ja").ToLowerInvariant();
                var tankName = (_tankEnmityNameCombo.Text ?? "").Trim();
                RefreshTankEnmityNameOptions(tankType, tankName);
            }
        }
        finally
        {
            _suppressEvents = false;
        }

        var job = _sessionMetaBySid.TryGetValue(sid, out var meta)
            ? meta.Job
            : SessionStateHelper.GetString(s, "job", "");
        if (!string.IsNullOrWhiteSpace(job))
        {
            _optionsHydratedJobBySid[sid] = job;
        }
        _optionsRequestInFlightBySid.Remove(sid);
        if (changed && string.Equals(_selectedSid, sid, StringComparison.Ordinal))
        {
            statusConnection.Text = $"Mirror: options hydrated ({metaOrJob(sid, job)})";
        }
    }

    private string metaOrJob(string sid, string fallbackJob)
    {
        if (_sessionMetaBySid.TryGetValue(sid, out var meta) && !string.IsNullOrWhiteSpace(meta.Job))
        {
            return meta.Job;
        }
        return string.IsNullOrWhiteSpace(fallbackJob) ? "unknown" : fallbackJob;
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
        _ignoreCurTarget.Enabled = true;
        _targetIgnCurTarget.Enabled = true;
        _addPriCurTarget.Enabled = true;

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
        _partnerCurTarget.Enabled = true;
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

        if (key == "Start_Engine")
        {
            Forward(sid, val ? new Dictionary<string, object?> { ["op"] = "start_engine" } : new Dictionary<string, object?> { ["op"] = "stop_engine" });
            _sessionRunningBySid[sid] = val;
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
            _pfFightFollowMinYalms.Enabled = val;
            _pfFightFollowHoldS.Enabled = val;
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

        var eng = GetEngineForSid(sid);
        var val = (_wsCombo.Text ?? "").Trim();
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

        var val = (_aftermathCombo.Text ?? "").Trim();
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "aftermath_ws", ["value"] = val });
    }

    private void RenderPathHunterList(JsonElement s)
    {
        var newRows = SessionStateHelper.ParseIgnoreEntriesFrom(s, "path_hunter_entries");
        if (newRows.SequenceEqual(_pathHunterRows) && _pathHunterList.Items.Count == newRows.Count)
        {
            return;
        }

        int? preserved = null;
        if (_pathHunterList.SelectedIndex >= 0 && _pathHunterRows.Count > 0 && _pathHunterList.SelectedIndex < _pathHunterRows.Count)
        {
            preserved = _pathHunterRows[_pathHunterList.SelectedIndex].Id;
        }

        _pathHunterRows = newRows;
        _pathHunterList.Items.Clear();
        foreach (var (_, name) in _pathHunterRows)
        {
            _pathHunterList.Items.Add(name);
        }

        if (preserved is { } pid)
        {
            for (var i = 0; i < _pathHunterRows.Count; i++)
            {
                if (_pathHunterRows[i].Id == pid)
                {
                    _pathHunterList.SelectedIndex = i;
                    break;
                }
            }
        }
    }

    private void RefreshPathPullActionNameOptions(string pullType, string selectedName)
    {
        var src = string.Equals(pullType, "spell", StringComparison.OrdinalIgnoreCase) ? _pathPullSpellOptions : _pathPullJaOptions;
        var incoming = selectedName ?? "";
        var next = new List<string>(src);

        var cur = _pathPullActionName.Items.Cast<object>().Select(x => x.ToString() ?? "").ToList();
        if (!SequenceEqualOrdinal(cur, next))
        {
            _pathPullActionName.Items.Clear();
            foreach (var n in next)
            {
                _pathPullActionName.Items.Add(n);
            }
        }

        var want = incoming;
        if (!string.IsNullOrEmpty(want))
        {
            var idx = next.FindIndex(x => string.Equals(x, want, StringComparison.Ordinal));
            _pathPullActionName.SelectedIndex = idx >= 0 ? idx : -1;
        }
        else
        {
            _pathPullActionName.SelectedIndex = -1;
        }
    }

    private void EnsureCorRollOptions(ComboBox combo)
    {
        if (combo.Items.Count > 0)
        {
            return;
        }

        combo.Items.Add("");
        foreach (var roll in HubUiConstants.CorRollOptions)
        {
            combo.Items.Add(roll);
        }
    }

    private void ApplyCorRollFromSnapshot(ComboBox combo, string value)
    {
        EnsureCorRollOptions(combo);

        if (combo.Focused || combo.DroppedDown)
        {
            return;
        }

        if (!string.IsNullOrEmpty(value) && !combo.Items.Cast<object>().Any(x => string.Equals(x?.ToString(), value, StringComparison.Ordinal)))
        {
            combo.Items.Insert(1, value);
        }

        var cur = combo.SelectedItem?.ToString() ?? "";
        if (string.Equals(cur, value, StringComparison.Ordinal))
        {
            return;
        }

        var idx = combo.Items.Cast<object>().ToList().FindIndex(x => string.Equals(x?.ToString(), value, StringComparison.Ordinal));
        combo.SelectedIndex = idx >= 0 ? idx : 0;
    }

    private void OnCorRollSelected(int slot)
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

        var combo = slot == 1 ? _corRoll1Combo : _corRoll2Combo;
        var path = slot == 1 ? "cor_roll_1" : "cor_roll_2";
        var val = combo.SelectedItem?.ToString() ?? "";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = path, ["value"] = val });
    }

    private void OnPathPartyGateChanged()
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

        var raw = (_pathPartyGateYalms.Text ?? "").Trim();
        if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var v))
        {
            v = 3.0;
        }
        if (v < 0.5)
        {
            v = 0.5;
        }
        else if (v > 50)
        {
            v = 50;
        }
        var normalized = v.ToString("0.###", CultureInfo.InvariantCulture);
        _pathPartyGateYalms.Text = normalized;
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "path_party_gate_yalms", ["value"] = normalized });
    }

    private void OnPathResumeIndexWindowChanged()
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

        var raw = (_pathResumeIndexWindow.Text ?? "").Trim();
        if (!int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v))
        {
            v = 12;
        }
        if (v < 1)
        {
            v = 1;
        }
        else if (v > 200)
        {
            v = 200;
        }
        var normalized = v.ToString(CultureInfo.InvariantCulture);
        _pathResumeIndexWindow.Text = normalized;
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "path_resume_index_window", ["value"] = normalized });
    }

    private void OnPathHunterMaxZDeltaChanged()
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

        var raw = (_pathHunterMaxZDelta.Text ?? "").Trim();
        if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var v))
        {
            v = 2.0;
        }
        if (v < 0)
        {
            v = 0;
        }
        else if (v > 20)
        {
            v = 20;
        }
        var normalized = v.ToString("0.###", CultureInfo.InvariantCulture);
        _pathHunterMaxZDelta.Text = normalized;
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "path_hunter_max_z_delta", ["value"] = normalized });
    }

    private void OnPathHunterMaxTargetRangeChanged()
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

        var raw = (_pathHunterMaxTargetRange.Text ?? "").Trim();
        if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var v))
        {
            v = 20.0;
        }
        if (v < 1)
        {
            v = 1;
        }
        else if (v > 80)
        {
            v = 80;
        }
        var normalized = v.ToString("0.###", CultureInfo.InvariantCulture);
        _pathHunterMaxTargetRange.Text = normalized;
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "path_hunter_max_target_range", ["value"] = normalized });
    }

    private void OnPathHunterClaimTimeoutChanged()
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

        var raw = (_pathHunterClaimTimeout.Text ?? "").Trim();
        if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var v))
        {
            v = 4.0;
        }
        if (v < 0.5)
        {
            v = 0.5;
        }
        else if (v > 30)
        {
            v = 30;
        }
        var normalized = v.ToString("0.###", CultureInfo.InvariantCulture);
        _pathHunterClaimTimeout.Text = normalized;
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "path_hunter_claim_timeout_s", ["value"] = normalized });
    }

    private void OnPathHunterIgnoreCooldownChanged()
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

        var raw = (_pathHunterIgnoreCooldown.Text ?? "").Trim();
        if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var v))
        {
            v = 20.0;
        }
        if (v < 0)
        {
            v = 0;
        }
        else if (v > 120)
        {
            v = 120;
        }
        var normalized = v.ToString("0.###", CultureInfo.InvariantCulture);
        _pathHunterIgnoreCooldown.Text = normalized;
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "path_hunter_ignore_cooldown_s", ["value"] = normalized });
    }

    private void OnPathPullActionTypeChanged()
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

        var at = _pathPullActionType.SelectedItem?.ToString() ?? "ja";
        at = string.Equals(at, "spell", StringComparison.OrdinalIgnoreCase) ? "spell" : "ja";
        _suppressEvents = true;
        try
        {
            RefreshPathPullActionNameOptions(at, _pathPullActionName.SelectedItem?.ToString() ?? "");
        }
        finally
        {
            _suppressEvents = false;
        }
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "path_pull_action_type", ["value"] = at });
    }

    private void OnPathPullActionNameChanged()
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

        var name = (_pathPullActionName.Text ?? "").Trim();
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "path_pull_action_name", ["value"] = name });
    }

    private void OnPathHunterAdd()
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

        var name = (_pathHunterName.Text ?? "").Trim();
        if (string.IsNullOrEmpty(name))
        {
            return;
        }
        if (!HasName(_pathHunterRows, name))
        {
            _pathHunterRows.Add((NextId(_pathHunterRows), name));
            RebindPathHunterListUi();
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "path_hunter_add", ["name"] = name });
        _pathHunterName.Text = "";
    }

    private void OnPathHunterRemove()
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

        var idx = _pathHunterList.SelectedIndex;
        if (idx < 0)
        {
            return;
        }
        if (idx < _pathHunterRows.Count)
        {
            _pathHunterRows.RemoveAt(idx);
            RebindPathHunterListUi();
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "path_hunter_remove", ["index"] = idx + 1 });
    }

    private static string NormalizeTankEnmityEntry(string type, string name)
    {
        var t = string.Equals(type, "spell", StringComparison.OrdinalIgnoreCase) ? "spell" : "ja";
        var n = (name ?? "").Trim();
        return n.Length == 0 ? "" : $"{t}:{n}";
    }

    private void RefreshTankEnmityNameOptions(string type, string selectedName)
    {
        var src = string.Equals(type, "spell", StringComparison.OrdinalIgnoreCase) ? _pathPullSpellOptions : _pathPullJaOptions;
        var next = new List<string>(src);
        var cur = _tankEnmityNameCombo.Items.Cast<object>().Select(x => x.ToString() ?? "").ToList();
        if (!SequenceEqualOrdinal(cur, next))
        {
            _tankEnmityNameCombo.Items.Clear();
            foreach (var n in next)
            {
                _tankEnmityNameCombo.Items.Add(n);
            }
        }

        var incoming = (selectedName ?? "").Trim();
        if (incoming.Length > 0)
        {
            var idx = next.FindIndex(x => string.Equals(x, incoming, StringComparison.Ordinal));
            _tankEnmityNameCombo.SelectedIndex = idx >= 0 ? idx : -1;
            if (idx < 0 && !_tankEnmityNameCombo.DroppedDown && !_tankEnmityNameCombo.Focused)
            {
                _tankEnmityNameCombo.Text = incoming;
            }
        }
        else if (!_tankEnmityNameCombo.DroppedDown)
        {
            _tankEnmityNameCombo.SelectedIndex = next.Count > 0 ? 0 : -1;
        }
    }

    private void PushTankEnmityActions(string sid)
    {
        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "tank_enmity_replace_actions",
                ["value"] = string.Join("|", _tankEnmityRows),
            }
        );
    }

    private void OnTankEnmityTypeChanged()
    {
        if (_suppressEvents)
        {
            return;
        }

        var at = _tankEnmityTypeCombo.SelectedItem?.ToString() ?? "ja";
        at = string.Equals(at, "spell", StringComparison.OrdinalIgnoreCase) ? "spell" : "ja";
        _suppressEvents = true;
        try
        {
            RefreshTankEnmityNameOptions(at, _tankEnmityNameCombo.Text ?? "");
        }
        finally
        {
            _suppressEvents = false;
        }
    }

    private void OnTankEnmityAdd()
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
        var at = _tankEnmityTypeCombo.SelectedItem?.ToString() ?? "ja";
        at = string.Equals(at, "spell", StringComparison.OrdinalIgnoreCase) ? "spell" : "ja";
        var name = (_tankEnmityNameCombo.Text ?? "").Trim();
        var entry = NormalizeTankEnmityEntry(at, name);
        if (entry.Length == 0)
        {
            return;
        }
        if (!_tankEnmityRows.Any(x => string.Equals(x, entry, StringComparison.OrdinalIgnoreCase)))
        {
            _tankEnmityRows.Add(entry);
            RebindTankEnmityListUi();
        }
        PushTankEnmityActions(sid);
    }

    private void OnTankEnmityRemove()
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
        var idx = _tankEnmityList.SelectedIndex;
        if (idx < 0 || idx >= _tankEnmityRows.Count)
        {
            return;
        }
        _tankEnmityRows.RemoveAt(idx);
        RebindTankEnmityListUi();
        PushTankEnmityActions(sid);
    }

    private void OnTankEnmityMove(string direction)
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
        var idx = _tankEnmityList.SelectedIndex;
        if (idx < 0 || idx >= _tankEnmityRows.Count)
        {
            return;
        }
        var next = string.Equals(direction, "up", StringComparison.OrdinalIgnoreCase) ? idx - 1 : idx + 1;
        if (next < 0 || next >= _tankEnmityRows.Count)
        {
            return;
        }
        (_tankEnmityRows[next], _tankEnmityRows[idx]) = (_tankEnmityRows[idx], _tankEnmityRows[next]);
        RebindTankEnmityListUi();
        _tankEnmityList.SelectedIndex = next;
        PushTankEnmityActions(sid);
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

    private void OnSpacingTuningBoolChanged()
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

        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_use_prediction", ["value"] = _spUsePrediction.Checked ? "on" : "off" });
        RememberPendingSpacingFromUi(sid);
    }

    private void OnSpacingTuningNumericChanged()
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

        string N(TextBox tb, double defV)
        {
            var raw = (tb.Text ?? "").Trim();
            if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var v))
            {
                v = defV;
            }

            var s = v.ToString("0.###", CultureInfo.InvariantCulture);
            tb.Text = s;
            return s;
        }

        string I(TextBox tb, int defV)
        {
            var raw = (tb.Text ?? "").Trim();
            if (!int.TryParse(raw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v))
            {
                v = defV;
            }

            var s = v.ToString(CultureInfo.InvariantCulture);
            tb.Text = s;
            return s;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_band_min", ["value"] = N(_spBandMin, -0.9) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_band_max", ["value"] = N(_spBandMax, 0.4) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_model_size_floor", ["value"] = N(_spModelSizeFloor, 0.9) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_lookahead_s", ["value"] = N(_spLookahead, 0.25) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_anchor_invalid_ticks", ["value"] = I(_spAnchorInvalidTicks, 5) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_emergency_margin", ["value"] = N(_spEmergencyMargin, 0.1) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_slot_switch_penalty", ["value"] = N(_spSwitchPenalty, 0.75) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_slot_switch_margin", ["value"] = N(_spSwitchMargin, 0.35) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_slot_arrival_tolerance", ["value"] = N(_spArrivalTolerance, 0.2) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_max_agents", ["value"] = I(_spMaxAgents, 6) });
        RememberPendingSpacingFromUi(sid);
    }

    private void OnGlobalSpacingAnchorChanged()
    {
        if (_suppressEvents)
        {
            return;
        }

        SaveGlobalUiSettings();
        PushGlobalAnchorSettingsToAllSessions();
    }

    private void RefreshGlobalAnchorMemberOptions()
    {
        var current = _spGlobalAnchorMember.SelectedItem?.ToString() ?? "";
        var names = CurrentPartyNameOptions();

        _suppressEvents = true;
        try
        {
            _spGlobalAnchorMember.Items.Clear();
            _spGlobalAnchorMember.Items.Add("");
            foreach (var name in names)
            {
                _spGlobalAnchorMember.Items.Add(name);
            }
            if (!string.IsNullOrWhiteSpace(current))
            {
                var exists = false;
                for (var i = 0; i < _spGlobalAnchorMember.Items.Count; i++)
                {
                    if (string.Equals(_spGlobalAnchorMember.Items[i]?.ToString() ?? "", current, StringComparison.Ordinal))
                    {
                        exists = true;
                        break;
                    }
                }
                if (!exists)
                {
                    _spGlobalAnchorMember.Items.Add(current);
                }
            }

            var idx = 0;
            for (var i = 0; i < _spGlobalAnchorMember.Items.Count; i++)
            {
                if (string.Equals(_spGlobalAnchorMember.Items[i]?.ToString() ?? "", current, StringComparison.Ordinal))
                {
                    idx = i;
                    break;
                }
            }
            _spGlobalAnchorMember.SelectedIndex = idx;
        }
        finally
        {
            _suppressEvents = false;
        }
    }

    private void PushGlobalAnchorSettingsToAllSessions()
    {
        foreach (var sid in _listSids)
        {
            PushGlobalAnchorSettingsToSid(sid);
        }
    }

    private void PushGlobalAnchorSettingsToSid(string sid)
    {
        if (string.IsNullOrWhiteSpace(sid))
        {
            return;
        }

        var enabled = _spGlobalAnchorEnabled.Checked;
        var name = (_spGlobalAnchorMember.SelectedItem?.ToString() ?? "").Trim();
        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "set",
                ["path"] = "spacing_global_anchor_enabled",
                ["value"] = enabled ? "on" : "off",
            }
        );
        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "set",
                ["path"] = "spacing_global_anchor_name",
                ["value"] = name,
            }
        );
    }

    private void RememberPendingSpacingFromUi(string sid)
    {
        _pendingSpacingBySid[sid] = (
            _spUsePrediction.Checked,
            (_spBandMin.Text ?? "").Trim(),
            (_spBandMax.Text ?? "").Trim(),
            (_spModelSizeFloor.Text ?? "").Trim(),
            (_spLookahead.Text ?? "").Trim(),
            (_spAnchorInvalidTicks.Text ?? "").Trim(),
            (_spEmergencyMargin.Text ?? "").Trim(),
            (_spSwitchPenalty.Text ?? "").Trim(),
            (_spSwitchMargin.Text ?? "").Trim(),
            (_spArrivalTolerance.Text ?? "").Trim(),
            (_spMaxAgents.Text ?? "").Trim(),
            DateTime.UtcNow
        );
    }

    private void PushPartyFollowDistances(string sid)
    {
        var minRaw = (_pfFollowMinYalms.Text ?? "").Trim();
        var maxRaw = (_pfFollowMaxYalms.Text ?? "").Trim();
        var fightMinRaw = (_pfFightFollowMinYalms.Text ?? "").Trim();
        var holdRaw = (_pfFightFollowHoldS.Text ?? "").Trim();
        if (!double.TryParse(minRaw, NumberStyles.Float, CultureInfo.InvariantCulture, out var minY))
        {
            minY = 0.5;
        }

        if (!double.TryParse(maxRaw, NumberStyles.Float, CultureInfo.InvariantCulture, out var maxY))
        {
            maxY = 50;
        }
        if (!double.TryParse(fightMinRaw, NumberStyles.Float, CultureInfo.InvariantCulture, out var fightMinY))
        {
            fightMinY = 3.0;
        }
        if (!double.TryParse(holdRaw, NumberStyles.Float, CultureInfo.InvariantCulture, out var holdS))
        {
            holdS = 8.0;
        }

        minY = Math.Clamp(minY, 0.01, 99.0);
        maxY = Math.Clamp(maxY, 0.1, 200.0);
        fightMinY = Math.Clamp(fightMinY, 0.01, 99.0);
        holdS = Math.Clamp(holdS, 0.0, 60.0);
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
        var fightMinS = fightMinY.ToString("0.###", CultureInfo.InvariantCulture);
        var holdSS = holdS.ToString("0.###", CultureInfo.InvariantCulture);
        _pfFollowMinYalms.Text = minS;
        _pfFollowMaxYalms.Text = maxS;
        _pfFightFollowMinYalms.Text = fightMinS;
        _pfFightFollowHoldS.Text = holdSS;
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "party_follow_min", ["value"] = minS });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "party_follow_max", ["value"] = maxS });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "fight_follow_min", ["value"] = fightMinS });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "fight_follow_hold_s", ["value"] = holdSS });
        _pendingPfDistBySid[sid] = (minS, maxS, fightMinS, holdSS, DateTime.UtcNow);
    }

    private static bool PartyFollowDistPairEcho(string srvMin, string srvMax, string srvFightMin, string srvHoldS, string pendMin, string pendMax, string pendFightMin, string pendHoldS)
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
        if (!double.TryParse(srvFightMin.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var e))
        {
            return false;
        }
        if (!double.TryParse(srvHoldS.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var f))
        {
            return false;
        }
        if (!double.TryParse(pendFightMin.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var g))
        {
            return false;
        }
        if (!double.TryParse(pendHoldS.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var h))
        {
            return false;
        }

        return Math.Abs(a - c) < 1e-9 && Math.Abs(b - d) < 1e-9 && Math.Abs(e - g) < 1e-9 && Math.Abs(f - h) < 1e-9;
    }

    private void ApplyPartyFollowDistancesFromSnapshot(string sid, JsonElement s)
    {
        var minSrv = SessionStateHelper.GetString(s, "party_follow_min", "0.5");
        var maxSrv = SessionStateHelper.GetString(s, "party_follow_max", "50");
        var fightMinSrv = SessionStateHelper.GetString(s, "fight_follow_min", "3");
        var holdSrv = SessionStateHelper.GetString(s, "fight_follow_hold_s", "8");

        if (_pfFollowMinYalms.Focused || _pfFollowMaxYalms.Focused || _pfFightFollowMinYalms.Focused || _pfFightFollowHoldS.Focused)
        {
            return;
        }

        if (_pendingPfDistBySid.TryGetValue(sid, out var pfd))
        {
            var ageSec = (DateTime.UtcNow - pfd.ts).TotalSeconds;
            if (PartyFollowDistPairEcho(minSrv, maxSrv, fightMinSrv, holdSrv, pfd.min, pfd.max, pfd.fightMin, pfd.holdS))
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
        if (!string.Equals(_pfFightFollowMinYalms.Text, fightMinSrv, StringComparison.Ordinal))
        {
            _pfFightFollowMinYalms.Text = fightMinSrv;
        }
        if (!string.Equals(_pfFightFollowHoldS.Text, holdSrv, StringComparison.Ordinal))
        {
            _pfFightFollowHoldS.Text = holdSrv;
        }
    }

    private static bool EquivalentNumericText(string left, string right)
    {
        if (string.Equals(left, right, StringComparison.Ordinal))
        {
            return true;
        }

        if (!double.TryParse(left.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var a))
        {
            return false;
        }

        if (!double.TryParse(right.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var b))
        {
            return false;
        }

        return Math.Abs(a - b) < 1e-9;
    }

    private static bool SpacingEchoMatches(
        bool srvUsePrediction,
        string srvBandMin,
        string srvBandMax,
        string srvModelSizeFloor,
        string srvLookahead,
        string srvAnchorInvalidTicks,
        string srvEmergencyMargin,
        string srvSwitchPenalty,
        string srvSwitchMargin,
        string srvArrivalTolerance,
        string srvMaxAgents,
        bool pendUsePrediction,
        string pendBandMin,
        string pendBandMax,
        string pendModelSizeFloor,
        string pendLookahead,
        string pendAnchorInvalidTicks,
        string pendEmergencyMargin,
        string pendSwitchPenalty,
        string pendSwitchMargin,
        string pendArrivalTolerance,
        string pendMaxAgents)
    {
        return srvUsePrediction == pendUsePrediction &&
               EquivalentNumericText(srvBandMin, pendBandMin) &&
               EquivalentNumericText(srvBandMax, pendBandMax) &&
               EquivalentNumericText(srvModelSizeFloor, pendModelSizeFloor) &&
               EquivalentNumericText(srvLookahead, pendLookahead) &&
               EquivalentNumericText(srvAnchorInvalidTicks, pendAnchorInvalidTicks) &&
               EquivalentNumericText(srvEmergencyMargin, pendEmergencyMargin) &&
               EquivalentNumericText(srvSwitchPenalty, pendSwitchPenalty) &&
               EquivalentNumericText(srvSwitchMargin, pendSwitchMargin) &&
               EquivalentNumericText(srvArrivalTolerance, pendArrivalTolerance) &&
               EquivalentNumericText(srvMaxAgents, pendMaxAgents);
    }

    private static void ApplyNumericTextIfChanged(TextBox tb, string incoming)
    {
        if (EquivalentNumericText(tb.Text ?? "", incoming))
        {
            return;
        }

        tb.Text = incoming;
    }

    private void ApplySpacingTuningFromSnapshot(string sid, JsonElement s)
    {
        var usePredictionSrv = SessionStateHelper.GetBool(s, "spacing_use_prediction", true);
        var bandMinSrv = SessionStateHelper.GetString(s, "spacing_band_min", "-0.9");
        var bandMaxSrv = SessionStateHelper.GetString(s, "spacing_band_max", "0.4");
        var modelSizeFloorSrv = SessionStateHelper.GetString(s, "spacing_model_size_floor", "0.9");
        var lookaheadSrv = SessionStateHelper.GetString(s, "spacing_lookahead_s", "0.25");
        var anchorInvalidTicksSrv = SessionStateHelper.GetString(s, "spacing_anchor_invalid_ticks", "5");
        var emergencyMarginSrv = SessionStateHelper.GetString(s, "spacing_emergency_margin", "0.1");
        var switchPenaltySrv = SessionStateHelper.GetString(s, "spacing_slot_switch_penalty", "0.75");
        var switchMarginSrv = SessionStateHelper.GetString(s, "spacing_slot_switch_margin", "0.35");
        var arrivalToleranceSrv = SessionStateHelper.GetString(s, "spacing_slot_arrival_tolerance", "0.2");
        var maxAgentsSrv = SessionStateHelper.GetString(s, "spacing_max_agents", "6");

        if (_spUsePrediction.Focused || _spBandMin.Focused || _spBandMax.Focused || _spModelSizeFloor.Focused || _spLookahead.Focused ||
            _spAnchorInvalidTicks.Focused || _spEmergencyMargin.Focused || _spSwitchPenalty.Focused ||
            _spSwitchMargin.Focused || _spArrivalTolerance.Focused || _spMaxAgents.Focused)
        {
            return;
        }

        if (_pendingSpacingBySid.TryGetValue(sid, out var ps))
        {
            var ageSec = (DateTime.UtcNow - ps.ts).TotalSeconds;
            var echoed = SpacingEchoMatches(
                usePredictionSrv, bandMinSrv, bandMaxSrv, modelSizeFloorSrv, lookaheadSrv, anchorInvalidTicksSrv, emergencyMarginSrv,
                switchPenaltySrv, switchMarginSrv, arrivalToleranceSrv, maxAgentsSrv,
                ps.usePrediction, ps.bandMin, ps.bandMax, ps.modelSizeFloor, ps.lookahead, ps.anchorInvalidTicks, ps.emergencyMargin,
                ps.switchPenalty, ps.switchMargin, ps.arrivalTolerance, ps.maxAgents
            );
            if (echoed)
            {
                _pendingSpacingBySid.Remove(sid);
            }
            else if (ageSec < 3.0)
            {
                return;
            }
            else
            {
                _pendingSpacingBySid.Remove(sid);
            }
        }

        if (_spUsePrediction.Checked != usePredictionSrv)
        {
            _spUsePrediction.Checked = usePredictionSrv;
        }

        ApplyNumericTextIfChanged(_spBandMin, bandMinSrv);
        ApplyNumericTextIfChanged(_spBandMax, bandMaxSrv);
        ApplyNumericTextIfChanged(_spModelSizeFloor, modelSizeFloorSrv);
        ApplyNumericTextIfChanged(_spLookahead, lookaheadSrv);
        ApplyNumericTextIfChanged(_spAnchorInvalidTicks, anchorInvalidTicksSrv);
        ApplyNumericTextIfChanged(_spEmergencyMargin, emergencyMarginSrv);
        ApplyNumericTextIfChanged(_spSwitchPenalty, switchPenaltySrv);
        ApplyNumericTextIfChanged(_spSwitchMargin, switchMarginSrv);
        ApplyNumericTextIfChanged(_spArrivalTolerance, arrivalToleranceSrv);
        ApplyNumericTextIfChanged(_spMaxAgents, maxAgentsSrv);
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
        var name = _abilityPickCombo.Text?.Trim() ?? _abilityPickCombo.SelectedItem?.ToString() ?? "";
        if (string.IsNullOrEmpty(name))
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
        if (!HasName(_ignoreRows, name))
        {
            _ignoreRows.Add((NextId(_ignoreRows), name));
            RebindIgnoreListUi();
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
        if (idx < _ignoreRows.Count)
        {
            _ignoreRows.RemoveAt(idx);
            RebindIgnoreListUi();
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
        if (!HasName(_partnerRows, name))
        {
            _partnerRows.Add((NextId(_partnerRows), name));
            RebindPartnerListUi();
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
        if (idx < _partnerRows.Count)
        {
            _partnerRows.RemoveAt(idx);
            RebindPartnerListUi();
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
        if (!HasName(_targetIgnoreRows, name))
        {
            _targetIgnoreRows.Add((NextSlot(_targetIgnoreRows), name));
            RebindTargetIgnoreListUi();
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
        if (idx < _targetIgnoreRows.Count)
        {
            _targetIgnoreRows.RemoveAt(idx);
            for (var i = 0; i < _targetIgnoreRows.Count; i++)
            {
                _targetIgnoreRows[i] = (i + 1, _targetIgnoreRows[i].Name);
            }
            RebindTargetIgnoreListUi();
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
        if (!HasName(_addPriorityRows, name))
        {
            _addPriorityRows.Add((NextSlot(_addPriorityRows), name));
            RebindAddPriorityListUi();
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
        if (idx < _addPriorityRows.Count)
        {
            _addPriorityRows.RemoveAt(idx);
            for (var i = 0; i < _addPriorityRows.Count; i++)
            {
                _addPriorityRows[i] = (i + 1, _addPriorityRows[i].Name);
            }
            RebindAddPriorityListUi();
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
        var localSlot = idx + 1;
        if (idx < _addPriorityRows.Count)
        {
            var next = string.Equals(direction, "up", StringComparison.OrdinalIgnoreCase) ? idx - 1 : idx + 1;
            if (next >= 0 && next < _addPriorityRows.Count)
            {
                (_addPriorityRows[next], _addPriorityRows[idx]) = (_addPriorityRows[idx], _addPriorityRows[next]);
                for (var i = 0; i < _addPriorityRows.Count; i++)
                {
                    _addPriorityRows[i] = (i + 1, _addPriorityRows[i].Name);
                }
                RebindAddPriorityListUi();
                _addPriList.SelectedIndex = next;
                localSlot = idx + 1;
            }
        }

        int? slot = localSlot;
        if (idx >= _addPriorityRows.Count)
        {
            slot = SessionStateHelper.ParseTrailingBracketId(_addPriList.Items[idx]?.ToString() ?? "") ?? 0;
        }
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

        TrySaveProfileFromUi(sid);
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

        var running = _sessionRunningBySid.TryGetValue(sid, out var rv) && rv;
        if (running)
        {
            Forward(sid, new Dictionary<string, object?> { ["op"] = "stop_engine" });
            _sessionRunningBySid[sid] = false;
        }
        else
        {
            Forward(sid, new Dictionary<string, object?> { ["op"] = "start_engine" });
            _sessionRunningBySid[sid] = true;
        }
    }

    private void ReloadAddonAndReapplyRun()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var wasRunning = _sessionRunningBySid.TryGetValue(sid, out var rv) && rv;
        if (_sessionMetaBySid.TryGetValue(sid, out var meta) && !string.IsNullOrWhiteSpace(meta.CharName))
        {
            if (wasRunning)
            {
                _pendingEngineReapplyByChar[meta.CharName] = DateTime.UtcNow.AddSeconds(60);
                statusConnection.Text = $"Mirror: reload sent ({meta.CharName}), queued run-state reapply";
            }
            else
            {
                _pendingEngineReapplyByChar.Remove(meta.CharName);
                statusConnection.Text = $"Mirror: reload sent ({meta.CharName})";
            }
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "addon_reload" });
    }

    private static int NextId(List<(int Id, string Name)> rows)
    {
        var mx = 0;
        foreach (var r in rows)
        {
            if (r.Id > mx)
            {
                mx = r.Id;
            }
        }
        return mx + 1;
    }

    private static int NextSlot(List<(int Slot, string Name)> rows)
    {
        var mx = 0;
        foreach (var r in rows)
        {
            if (r.Slot > mx)
            {
                mx = r.Slot;
            }
        }
        return mx + 1;
    }

    private static bool HasName(IEnumerable<(int, string)> rows, string name)
    {
        return rows.Any(r => string.Equals(r.Item2, name, StringComparison.OrdinalIgnoreCase));
    }

    private void RebindIgnoreListUi()
    {
        _ignoreList.Items.Clear();
        foreach (var (id, name) in _ignoreRows)
        {
            _ignoreList.Items.Add($"{name} [{id}]");
        }
    }

    private void RebindPartnerListUi()
    {
        _partnerList.Items.Clear();
        foreach (var (id, name) in _partnerRows)
        {
            _partnerList.Items.Add($"{name} [{id}]");
        }
    }

    private void RebindTargetIgnoreListUi()
    {
        _targetIgnList.Items.Clear();
        foreach (var (slot, name) in _targetIgnoreRows)
        {
            _targetIgnList.Items.Add($"{name} [{slot}]");
        }
    }

    private void RebindAddPriorityListUi()
    {
        _addPriList.Items.Clear();
        foreach (var (slot, name) in _addPriorityRows)
        {
            _addPriList.Items.Add($"{name} [{slot}]");
        }
    }

    private void RebindPathHunterListUi()
    {
        _pathHunterList.Items.Clear();
        foreach (var (_, name) in _pathHunterRows)
        {
            _pathHunterList.Items.Add(name);
        }
    }

    private void RebindTankEnmityListUi()
    {
        _tankEnmityList.Items.Clear();
        foreach (var entry in _tankEnmityRows)
        {
            _tankEnmityList.Items.Add(entry);
        }
    }

    private void PushFullFormState(string sid)
    {
        var eng = GetEngineForSid(sid);
        var wsVal = (_wsCombo.Text ?? "").Trim();
        SendWsUpdate(sid, eng, wsVal);
        SendAbilitiesUpdate();
        Forward(sid, new Dictionary<string, object?> { ["op"] = "ignore_replace_names", ["value"] = string.Join("|", _ignoreRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "partner_replace_names", ["value"] = string.Join("|", _partnerRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "target_ignore_replace_names", ["value"] = string.Join("|", _targetIgnoreRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "add_priority_replace_names", ["value"] = string.Join("|", _addPriorityRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "path_hunter_replace_names", ["value"] = string.Join("|", _pathHunterRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "tank_enmity_replace_actions", ["value"] = string.Join("|", _tankEnmityRows) });
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
        PushGlobalAnchorSettingsToSid(sid);
        UpdateBooleanCardVisuals();
    }
}
