using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace UnifiedCombatWinForms;

public partial class MainForm
{
    private sealed record ReactionRuleRow(
        string Trigger,
        string Name,
        string Response,
        double? Distance,
        string? ActionType = null,
        string? ActionName = null,
        string? ActivateEvent = null,
        string? ReleaseEvent = null,
        string? ReleaseName = null,
        double? ConfirmationTimeoutSeconds = null
    );
    private sealed record NamedFormationRow(string MobName, JsonObject Geometry);

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

    internal static List<string> ComputeSelectedAbilitiesFromState(JsonElement s)
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

            if (outl.Any(x => string.Equals(x, a, StringComparison.Ordinal)))
            {
                continue;
            }

            outl.Add(a);
        }

        return outl;
    }

    private sealed class PartyChoice
    {
        public string Name { get; }
        public bool IsUc { get; }

        public PartyChoice(string name, bool isUc)
        {
            Name = name ?? "";
            IsUc = isUc;
        }

        public override string ToString()
        {
            if (string.IsNullOrWhiteSpace(Name))
            {
                return "";
            }
            return $"{Name} [{(IsUc ? "UC" : "party")}]";
        }
    }

    private HashSet<string> GetUcNameSet()
    {
        return _sessionMetaBySid.Values
            .Select(x => x.CharName ?? "")
            .Where(x => !string.IsNullOrWhiteSpace(x))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
    }

    private string SelectedPartyName(ComboBox combo)
    {
        var raw = combo.SelectedItem switch
        {
            PartyChoice pc => pc.Name,
            _ => combo.SelectedItem?.ToString() ?? combo.Text ?? "",
        };
        return NormalizePartyName(raw);
    }

    private static string NormalizePartyName(string? value)
    {
        var n = (value ?? "").Trim();
        if (string.IsNullOrEmpty(n))
        {
            return "";
        }
        const string ucSuffix = " [UC]";
        const string partySuffix = " [party]";
        if (n.EndsWith(ucSuffix, StringComparison.OrdinalIgnoreCase))
        {
            return n[..^ucSuffix.Length].Trim();
        }
        if (n.EndsWith(partySuffix, StringComparison.OrdinalIgnoreCase))
        {
            return n[..^partySuffix.Length].Trim();
        }
        return n;
    }

    private bool ComboContainsPartyName(ComboBox combo, string name)
    {
        name = NormalizePartyName(name);
        if (string.IsNullOrWhiteSpace(name))
        {
            return true;
        }
        foreach (var item in combo.Items.Cast<object>())
        {
            if (item is PartyChoice pc && string.Equals(pc.Name, name, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
            if (item is string s && string.Equals(s, name, StringComparison.OrdinalIgnoreCase))
            {
                return true;
            }
        }
        return false;
    }

    private void BindPartyCombo(ComboBox combo, IReadOnlyList<string> rawNames, string selectedName)
    {
        selectedName = NormalizePartyName(selectedName);
        var ucNames = GetUcNameSet();
        var list = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var n in rawNames)
        {
            var t = (n ?? "").Trim();
            if (string.IsNullOrEmpty(t) || !seen.Add(t))
            {
                continue;
            }
            list.Add(t);
        }

        combo.Items.Clear();
        combo.Items.Add(new PartyChoice("", true));
        foreach (var n in list)
        {
            combo.Items.Add(new PartyChoice(n, ucNames.Contains(n)));
        }

        if (!string.IsNullOrWhiteSpace(selectedName) && !list.Any(x => string.Equals(x, selectedName, StringComparison.OrdinalIgnoreCase)))
        {
            combo.Items.Add(new PartyChoice(selectedName, ucNames.Contains(selectedName)));
        }

        var idx = 0;
        for (var i = 0; i < combo.Items.Count; i++)
        {
            if (combo.Items[i] is PartyChoice pc && string.Equals(pc.Name, selectedName, StringComparison.OrdinalIgnoreCase))
            {
                idx = i;
                break;
            }
        }
        combo.SelectedIndex = idx;
    }

    private List<string> CurrentSelectablePartyNameOptions(IReadOnlyList<string> reportedPartyNames)
    {
        var selectedCharacter = _selectedSid is not null
            && _sessionMetaBySid.TryGetValue(_selectedSid, out var selectedMeta)
                ? selectedMeta.CharName
                : "";
        return reportedPartyNames
            .Concat(CurrentPartyNameOptions())
            .Select(NormalizePartyName)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Where(name => !string.Equals(name, selectedCharacter, StringComparison.OrdinalIgnoreCase))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private void UpdatePartyFollowModeWarning(string sid)
    {
        if (_partyFollowModeWarning is null)
        {
            return;
        }
        var selected = SelectedPartyName(_partyFollowCombo);
        var partyFollowOn = _boolChecks.TryGetValue("party_follow", out var cb) && cb.Checked;
        var isUc = GetUcNameSet().Contains(selected);
        var show = partyFollowOn && !string.IsNullOrWhiteSpace(selected) && !isUc;
        _partyFollowModeWarning.Visible = show;
        _partyFollowModeWarning.Text = show
            ? "Non-UC follow target selected; precision may be lower."
            : "";
    }

    private string FormatPartyDisplayName(string name)
    {
        var n = (name ?? "").Trim();
        if (string.IsNullOrWhiteSpace(n))
        {
            return n;
        }
        var partyKnown = _partyOptions.Any(x => string.Equals(x, n, StringComparison.OrdinalIgnoreCase));
        if (!partyKnown)
        {
            return n;
        }
        var isUc = GetUcNameSet().Contains(n);
        return $"{n} [{(isUc ? "UC" : "party")}]";
    }

    private void RefreshEditorFromSnapshot()
    {
        if (string.IsNullOrEmpty(_selectedSid))
        {
            ClearForm();
            return;
        }
        if (TryLoadWorkingProfileForSid(_selectedSid, out var profileDoc))
        {
            using (profileDoc)
            {
                FillFromSession(_selectedSid, profileDoc.RootElement);
            }
            return;
        }
        if (_snapshotDoc is null
            || !_snapshotDoc.RootElement.TryGetProperty("sessions", out var sessions)
            || !sessions.TryGetProperty(_selectedSid, out var session)
            || !session.TryGetProperty("active_config", out var activeConfig)
            || activeConfig.ValueKind != JsonValueKind.Object)
        {
            ClearForm();
            return;
        }
        var editorProfile = RuntimeProfileEditorAdapter.Build(session, activeConfig);
        using var activeProfileDoc = JsonDocument.Parse(editorProfile.ToJsonString());
        FillFromSession(_selectedSid, activeProfileDoc.RootElement);
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
            var incoming = SessionStateHelper.GetBool(s, key, string.Equals(key, "auto_engage", StringComparison.Ordinal));
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
            var wsMode = SessionStateHelper.GetString(s, "ws_mode", "smart");
            _wsModeCombo.SelectedItem = WsModeRuntimeToUi(wsMode);
            _wsMinimumTp.Value = ReadWeaponskillMinimumTp(s);
            _foodEnabled.Checked = SessionStateHelper.GetBool(s, "food_enabled", false);
            _foodItem.Text = SessionStateHelper.GetString(s, "food_item", "");
            _chkWsAllowAoe.Checked = SessionStateHelper.GetBool(s, "weaponskill_allow_aoe", true);
            _chkFastSkillchain.Checked = SessionStateHelper.GetBool(s, "fast_skillchain", false);
            _skillchainTargetCombo.SelectedItem = SkillchainTargetRuntimeToUi(
                SessionStateHelper.GetString(s, "skillchain_target", "auto")
            );
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
        RenderNoSkillchainTargetList(s);
        RenderAddPriorityList(s);
        RenderSleepSpellList(s);
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
            if (_boolChecks.TryGetValue("auto_engage", out var autoEngage))
            {
                autoEngage.Checked = true;
            }

            _wsCombo.Items.Clear();
            _wsModeCombo.SelectedItem = "Smart";
            _wsMinimumTp.Value = 1000;
            _foodEnabled.Checked = false;
            _foodItem.Text = "";
            _chkWsAllowAoe.Checked = true;
            _chkFastSkillchain.Checked = false;
            _skillchainTargetCombo.SelectedItem = "Auto";
            _magicBurstEnabled.Checked = false;
            _magicBurstSpell.Items.Clear();
            _magicBurstSpell.Text = "";
            _magicBurstMaxTier.Items.Clear();
            _magicBurstMaxTier.Items.Add("Auto");
            _magicBurstMaxTier.SelectedItem = "Auto";
            _magicBurstMaxTier.Enabled = false;
            _pullerCombo.Items.Clear();
			_pullerLeashSource.SelectedItem = "Player";
			_campStatus.Text = "Camp not set";
            _fightLeaderCombo.Items.Clear();
            _partyFollowCombo.Items.Clear();
			_nyzulCoordinatorCombo.Items.Clear();
			_nyzulAnchorCombo.Items.Clear();
			_nyzulParkerCombo.Items.Clear();
			_nyzulParkingList.Items.Clear();
			_nyzulParkingOrder.Clear();
            _aftermathCombo.Items.Clear();
            _aftermathCombo.Enabled = false;
            _defProviderCombo.SelectedIndex = _defProviderCombo.Items.IndexOf("internal");
            if (_defProviderCombo.SelectedIndex < 0)
            {
                _defProviderCombo.SelectedIndex = 0;
            }

            _defCrit.Text = "35";
            _defMed.Text = "55";
            _defNaPriority.Text = "";
            _defOverwrite.Text = "150";
            _defBuffs.Text = "";
            _defTargetedBuffs.Text = "";
            _defEnemyDebuffs.Text = "";
            _pfFollowMinYalms.Text = "0.5";
            _pfFollowMaxYalms.Text = "50";
            _pfFightFollowMinYalms.Text = "3";
            _pfFightFollowHoldS.Text = "8";
            _pullerEngageRange.Text = "6";
            _sleepMaxTargetRange.Text = "6";
            _spUsePrediction.Checked = true;
            _spBandMin.Text = "-0.9";
            _spBandMax.Text = "0.4";
            _spModelSizeFloor.Text = "0.9";
            _spLookahead.Text = "0.25";
            _spAnchorInvalidTicks.Text = "5";
            _spEmergencyMargin.Text = "0.1";
            _spSwitchMargin.Text = "0.35";
            _spArrivalTolerance.Text = "0.2";
            _encounterEnabled.Checked = false;
            _encounterId.SelectedItem = "Ghatjot — Sortie Area A";
            _encounterWaterDamage.SelectedItem = "Enforce";
            _encounterWaterSkillchain.SelectedItem = "Enforce";
            _encounterRepeatActionWall.SelectedItem = "Off";
            _encounterRepeatActionGuard.Value = 10.0m;
            _keiElementalDealer.Items.Clear();
            _keiElementalDealer.Text = "";
            _keiWaterProbeSpell.Text = "Water";
            _keiWaterDamageSpell.Text = "Water III";
            _keiIceProbeSpell.Text = "Blizzard";
            _keiIceDamageSpell.Text = "Blizzard III";
            _keiSustainInterval.Value = 2.5m;
            _keiProbeTimeout.Value = 3.0m;
            _keiFullersTargetDistance.Value = 12.0m;
            _keiFullersPrearmMargin.Value = 1.0m;
            _formationEnabled.Checked = false;
            _namedFormationsEnabled.Checked = false;
            _namedFormationMobName.Text = "";
            _namedFormations.Clear();
            _namedFormationList.Items.Clear();
            _formationEncounter.SelectedItem = "Lady Lilith — Easy";
            _formationMockEnabled.Checked = false;
            _formationMockMobName.Text = "";
            _formationRole.SelectedItem = "Disabled";
            _formationTankName.Items.Clear();
            _formationTankName.Text = "";
            _formationRequiredParty.Items.Clear();
            _formationCaptureStable.Value = 0.50m;
            _formationCaptureTolerance.Value = 0.10m;
            _formationSafeRadius.Value = 16.0m;
            _formationTankAcceptRadius.Value = 1.5m;
            _formationTankReturnRadius.Value = 3.0m;
            _formationDpsFlankAngle.Value = 90.0m;
            _formationDpsMeleeRadius.Value = 3.0m;
            _formationDpsPositionTolerance.Value = 1.5m;
            _formationHealerPreferredRadius.Value = 12.0m;
            _formationHealerMinimumBossDistance.Value = 8.0m;
            _formationHealerMaximumPartyRange.Value = 18.0m;
            _formationHealerConeHalfAngle.Value = 50.0m;
            _formationHealerConeSafetyMargin.Value = 15.0m;
            _formationHealerSampleStep.Value = 10.0m;
            _formationPlacementMode.SelectedItem = "Radial band";
            _formationAnchor.SelectedItem = "Boss";
            _formationAnchorMember.Items.Clear();
            _formationAnchorMember.Text = "";
            _formationAxisType.SelectedItem = "Boss to member";
            _formationAxisMember.Items.Clear();
            _formationAxisMember.Text = "";
            _formationPreferredRadius.Value = 3.0m;
            _formationMinimumRadius.Value = 2.0m;
            _formationMaximumRadius.Value = 4.0m;
            _formationPreferredAngle.Value = 180.0m;
            _formationAllowedAngleHalfWidth.Value = 60.0m;
            _formationRadiusStep.Value = 0.5m;
            _formationAngleStep.Value = 10.0m;
            _formationHysteresisStart.Value = 1.0m;
            _formationHysteresisStop.Value = 0.5m;
            _formationAvoidEncounterHazards.Checked = false;
            _formationHazardMargin.Value = 0.0m;
            _formationSafeOriginRadius.Value = 0.0m;
            _formationMinimumBossDistance.Value = 0.0m;
            _formationMaximumBossDistance.Value = 0.0m;
            _formationMaximumPartyRange.Value = 0.0m;
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
            ResetGeoPullUi();
            EnsureGeoTabVisibility(false);
            EnsureSummonerTabVisibility(false);
            EnsurePuppetmasterTabVisibility(false);
            EnsureScholarTabVisibility(false);
            _tankEnmityList.Items.Clear();
            _tankEnmityRows = [];
            _tankEnmityTypeCombo.SelectedItem = "ja";
            _tankEnmityNameCombo.Items.Clear();
            _tankEnmityNameCombo.Text = "";
            _runTankEnabled.Checked = false;
            _runNoTpMode.Checked = false;
            _runRunesMaintain.Checked = true;
            _runRunes.Text = "";
            _runFoil.Checked = true;
            _runVallation.Checked = false;
            _runValiance.Checked = false;
            _runPflug.Checked = false;
            _runSwordplay.Checked = false;
            _runBattuta.Checked = false;
            _runOneForAll.Checked = false;
            _runGambit.Checked = false;
            _runRayke.Checked = false;
            _pathHunterName.Text = "";
            _corRoll1Combo.Items.Clear();
            _corRoll2Combo.Items.Clear();
            _corRoll1Combo.Enabled = false;
            _corRoll2Combo.Enabled = false;
            _corCrookedRoll1.Checked = false;
            _corCrookedRoll2.Checked = false;
            _corCrookedRoll1.Enabled = false;
            _corCrookedRoll2.Enabled = false;
            _corElevens.Checked = false;
            _corLuzafRangeOverride.Checked = false;
            _corElevens.Enabled = false;
            _corLuzafRangeOverride.Enabled = false;
            _corRangePartyPanel.Controls.Clear();
            _corRollOptions.Clear();
            _corPartyOptions.Clear();
            _summonerEnabled.Checked = false;
            _summonerAvatar.SelectedIndex = 0;
            _summonerAvatarFavor.Checked = false;
            _summonerWardEnabled.Checked = false;
			BindSummonerWardList([]);
            _summonerEngage.Checked = false;
            _summonerRageEnabled.Checked = false;
            BindSummonerActionCombo(_summonerRageAction, [], "");
            _summonerRageTargetHppAboveEnabled.Checked = false;
            _summonerRageTargetHppAbove.Value = 50;
            _summonerRagePetTpAboveEnabled.Checked = false;
            _summonerRagePetTpAbove.Value = 2000;
            UpdateSummonerUiState();
            ResetPuppetmasterUi();
            _schEnabled.Checked = false;
            _schArtsMinimumCommit.Value = 12;
            _schArtsEmergencyOffArtCasts.Checked = true;
            _schRegenEnabled.Checked = false;
            _schRegenMinimumCoverage.Value = 4;
            _schRegenRefreshBefore.Value = 25;
            _schStormsEnabled.Checked = false;
            _schStormAssignments.Text = "";
            _schStormsRefreshBefore.Value = 30;
            _schSublimationEnabled.Checked = false;
            _schSublimationReleaseMpp.Value = 45;
            _schSublimationReleaseComplete.Checked = false;
            _schSublimationMinimumHpp.Value = 75;
            UpdateScholarUiState();
            _reactionEnabled.Checked = false;
            _reactionRules.Clear();
            _reactionRuleList.Items.Clear();
            _reactionName.Text = "";
            _reactionDistance.Value = 12m;
            _reactionActionType.SelectedItem = "spell";
            _reactionActionName.Items.Clear();
            _reactionActionName.Text = "";
            _reactionTriggerCombo.SelectedItem = "ability_window";
            RefreshReactionResponseOptions();
            _partyOptions.Clear();
            _partyFollowModeWarning.Visible = false;
            _partyFollowModeWarning.Text = "";
            _ignoreName.Text = "";
            _targetIgnName.Text = "";
            _addPriName.Text = "";
            _sleepSpellName.Text = "";
            _partnerName.Text = "";
            _abilityList.Items.Clear();
            _abilityPickCombo.Items.Clear();
            _ignoreList.Items.Clear();
            _partnerList.Items.Clear();
            _targetIgnList.Items.Clear();
            _noSkillchainTargetList.Items.Clear();
            _addPriList.Items.Clear();
            _sleepSpellList.Items.Clear();
            _ignoreRows = [];
            _partnerRows = [];
            _targetIgnoreRows = [];
            _noSkillchainTargetRows = [];
            _addPriorityRows = [];
            _sleepSpellRows = [];
            _selectedAbilities.Clear();
            _abilityOptions.Clear();
            _ignoreCurTarget.Enabled = false;
            _targetIgnCurTarget.Enabled = false;
            _noSkillchainTargetCurrent.Enabled = false;
            _addPriCurTarget.Enabled = false;
            _partnerCurTarget.Enabled = false;
            _pullerCombo.Enabled = false;
            _pullerEngageRange.Enabled = false;
            _sleepMaxTargetRange.Enabled = false;
            _fightLeaderCombo.Enabled = false;
            _partyFollowCombo.Enabled = false;
            _pfFollowMinYalms.Enabled = false;
            _pfFollowMaxYalms.Enabled = false;
            _pfFightFollowMinYalms.Enabled = false;
            _pfFightFollowHoldS.Enabled = false;
            UpdateEncounterUiState();
            UpdateFormationUiState();
            UpdateBooleanCardVisuals();
        }
        finally
        {
            _suppressEvents = false;
        }
    }

    private void FillFromSession(string sid, JsonElement s)
    {
        var compatibilityBools = new Dictionary<string, bool>(StringComparer.Ordinal);
        foreach (var key in HubUiConstants.CompatibilityOnlyBoolKeys)
        {
            compatibilityBools[key] = SessionStateHelper.GetBool(s, key, false);
        }
        _compatibilityBoolBySid[sid] = compatibilityBools;

        if (sid != _lastFillSid)
        {
            _lastFillSid = sid;
            _ignoreRows = [];
            _partnerRows = [];
            _targetIgnoreRows = [];
            _addPriorityRows = [];
            _sleepSpellRows = [];
			_nyzulParkingOrder.Clear();
        }

        var eng = SessionStateHelper.GetString(s, "engine", "melee");
        var signature = SessionStateHelper.AbilitySignature(s);
        _abilitySignatureBySid[sid] = signature;

        var abilityOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("ability_options", out var ao) ? ao : default);
        var wsOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("weaponskill_options", out var wso) ? wso : default);
        var pullJaOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("path_pull_ja_options", out var pjo) ? pjo : default);
        var pullSpellOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("path_pull_spell_options", out var pso) ? pso : default);
        var resurrectionOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("resurrection_options", out var rso) ? rso : default);
        var tankEnmityActions = SessionStateHelper.SplitOptions(s.TryGetProperty("tank_enmity_actions", out var tea) ? tea : default);
        var partyOptsLive = CurrentSelectablePartyNameOptions(
            SessionStateHelper.SplitOptions(s.TryGetProperty("party_options", out var pto) ? pto : default)
        );
        if (!SequenceEqualOrdinal(_partyOptions, partyOptsLive))
        {
            _partyOptions.Clear();
            _partyOptions.AddRange(partyOptsLive);
        }
        if (!SequenceEqualOrdinal(_corPartyOptions, partyOptsLive))
        {
            _corPartyOptions.Clear();
            _corPartyOptions.AddRange(partyOptsLive);
        }
        var partnerOpts = _partyOptions.Count > 0
            ? new List<string>(_partyOptions)
            : SessionStateHelper.SplitOptions(s.TryGetProperty("partner_options", out var po) ? po : default);
        var pullerOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("puller_options", out var plo) ? plo : default);
        if (pullerOpts.Count == 0)
        {
            pullerOpts = new List<string>(partnerOpts);
        }

        _suppressEvents = true;
        try
        {
            if (!SequenceEqualOrdinal(_abilityOptions, abilityOpts))
            {
                _abilityOptions.Clear();
                _abilityOptions.AddRange(abilityOpts);
            }

            var nextSelected = ComputeSelectedAbilitiesFromState(s);
            if (!SequenceEqualOrdinal(_selectedAbilities, nextSelected))
            {
                _selectedAbilities.Clear();
                _selectedAbilities.AddRange(nextSelected);
            }
            SyncAbilityListUi();

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
            var wsMode = SessionStateHelper.GetString(s, "ws_mode", "smart");
            _wsModeCombo.SelectedItem = WsModeRuntimeToUi(wsMode);
            _wsMinimumTp.Value = ReadWeaponskillMinimumTp(s);
            _chkWsAllowAoe.Checked = SessionStateHelper.GetBool(s, "weaponskill_allow_aoe", true);
            _chkFastSkillchain.Checked = SessionStateHelper.GetBool(s, "fast_skillchain", false);
            _skillchainTargetCombo.SelectedItem = SkillchainTargetRuntimeToUi(
                SessionStateHelper.GetString(s, "skillchain_target", "auto")
            );
            ApplyMagicBurstFromSnapshot(s);
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

            var pullOn = SessionStateHelper.GetBool(s, "puller", false);
            var selPull = NormalizePartyName(SessionStateHelper.GetString(s, "puller_selected"));
			var leashSource = SessionStateHelper.GetString(s, "puller_leash_source", "player").Trim().ToLowerInvariant();
			if (leashSource is not ("player" or "camp"))
			{
				throw new InvalidDataException($"Invalid puller leash source '{leashSource}'.");
			}
			_pullerLeashSource.SelectedItem = leashSource == "camp" ? "Camp" : "Player";

            BindPartyCombo(_pullerCombo, pullerOpts, selPull);
			_pullerCombo.Enabled = pullOn && leashSource == "player";
			_pullerLeashSource.Enabled = pullOn;
            _pullerEngageRange.Text = SessionStateHelper.GetString(s, "puller_engage_range", "6");
            _pullerEngageRange.Enabled = pullOn;
			_campSet.Enabled = pullOn && leashSource == "camp";
			_campClear.Enabled = pullOn && leashSource == "camp";
			_campStatus.Text = leashSource == "camp" ? "Waiting for addon state…" : "Camp mode inactive";
            _sleepMaxTargetRange.Text = SessionStateHelper.GetString(s, "sleep_max_target_range", "6");

            var flOn = SessionStateHelper.GetBool(s, "fight_leader", false);
            var selFl = NormalizePartyName(SessionStateHelper.GetString(s, "fight_leader_selected"));

            BindPartyCombo(_fightLeaderCombo, partnerOpts, selFl);
            _fightLeaderCombo.Enabled = flOn;

            var pfOn = SessionStateHelper.GetBool(s, "party_follow", false);
            var selPf = NormalizePartyName(SessionStateHelper.GetString(s, "party_follow_selected"));

            BindPartyCombo(_partyFollowCombo, partnerOpts, selPf);
            _partyFollowCombo.Enabled = pfOn;
            UpdatePartyFollowModeWarning(sid);

			var nyzulCoordinator = NormalizePartyName(SessionStateHelper.GetString(s, "nyzul_coordinator_name"));
			var nyzulAnchor = NormalizePartyName(SessionStateHelper.GetString(s, "nyzul_anchor_name"));
			BindPartyCombo(_nyzulCoordinatorCombo, partnerOpts, nyzulCoordinator);
			BindPartyCombo(_nyzulAnchorCombo, partnerOpts, nyzulAnchor);
			BindPartyCombo(_nyzulParkerCombo, partnerOpts, "");
			_nyzulParkingOrder.Clear();
			_nyzulParkingOrder.AddRange(SessionStateHelper.SplitOptions(
				s.TryGetProperty("nyzul_parking_order", out var nyzulOrder) ? nyzulOrder : default
			));
			RebindNyzulParkingList();

            _pfFollowMinYalms.Enabled = pfOn;
            _pfFollowMaxYalms.Enabled = pfOn;
            _pfFightFollowMinYalms.Enabled = pfOn;
            _pfFightFollowHoldS.Enabled = pfOn;
            ApplyPartyFollowDistancesFromSnapshot(sid, s);
            ApplySpacingTuningFromSnapshot(sid, s);
            ApplyEncounterConfigFromSnapshot(s);
            ApplyFormationConfigFromSnapshot(s, partnerOpts);

            var prov = SessionStateHelper.GetString(s, "defensive_provider", "internal");
            if (prov != "internal" && prov != "healbot")
            {
                prov = "internal";
            }

            _defProviderCombo.SelectedItem = prov;

            _defCrit.Text = SessionStateHelper.GetString(s, "defensive_critical_hpp", "35");
            _defMed.Text = SessionStateHelper.GetString(s, "defensive_medium_hpp", "55");
            _defHealMinTier.Text = SessionStateHelper.GetString(s, "def_heal_min_tier_cure", "3");
            _defHealMaxTier.Text = SessionStateHelper.GetString(s, "def_heal_max_tier_cure", "4");
            _defHealMinMissingHp.Text = SessionStateHelper.GetString(s, "def_heal_min_missing_hp", "250");
            _defHealIgnoreTrusts.Checked = SessionStateHelper.GetBool(s, "def_heal_ignore_trusts", true);
            if (!SequenceEqualOrdinal(_defResurrectionOptions, resurrectionOpts))
            {
                _defResurrectionOptions.Clear();
                _defResurrectionOptions.AddRange(resurrectionOpts);
            }
            ApplyDefResurrectionPriority(s);
            RefreshDefResurrectionOptions();
            _defCuragaMinTargets.Value = Math.Clamp(SessionStateHelper.GetInt(s, "defensive_curaga_min_targets", 3), 2, 6);
            _defWaltzTpReserve.Value = Math.Clamp(SessionStateHelper.GetInt(s, "defensive_waltz_tp_reserve", 0), 0, 3000);
            _defDivineWaltzMinTargets.Value = Math.Clamp(SessionStateHelper.GetInt(s, "defensive_divine_waltz_min_targets", 3), 2, 6);
            _defNaPriority.Text = SessionStateHelper.GetString(s, "defensive_na_priority");
            _defOverwrite.Text = SessionStateHelper.GetString(s, "defensive_overwrite_interval", "150");
            _defBuffs.Text = SessionStateHelper.GetString(s, "defensive_buffs");
            _defTargetedBuffs.Text = SessionStateHelper.GetString(s, "defensive_targeted_buffs");
            _defEnemyDebuffs.Text = SessionStateHelper.GetString(s, "defensive_enemy_debuffs");

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
                RefreshKeiSpellOptions();
                UpdateEncounterUiState();
                RefreshMagicBurstSpellOptions();
                RefreshReactionActionSpellOptions();
            }
            if (!SequenceEqualOrdinal(_tankEnmityRows, tankEnmityActions))
            {
                _tankEnmityRows = tankEnmityActions.Where(x => !string.IsNullOrWhiteSpace(x)).ToList();
                RebindTankEnmityListUi();
            }
            _runTankEnabled.Checked = SessionStateHelper.GetBool(s, "run_tank_enabled", false);
            _runNoTpMode.Checked = SessionStateHelper.GetBool(s, "run_tank_no_tp_mode", false);
            _runRunesMaintain.Checked = SessionStateHelper.GetBool(s, "run_tank_runes_maintain", true);
            _runRunes.Text = SessionStateHelper.GetString(s, "run_tank_runes");
            _runFoil.Checked = SessionStateHelper.GetBool(s, "run_tank_foil", true);
            _runVallation.Checked = SessionStateHelper.GetBool(s, "run_tank_vallation", false);
            _runValiance.Checked = SessionStateHelper.GetBool(s, "run_tank_valiance", false);
            _runPflug.Checked = SessionStateHelper.GetBool(s, "run_tank_pflug", false);
            _runSwordplay.Checked = SessionStateHelper.GetBool(s, "run_tank_swordplay", false);
            _runBattuta.Checked = SessionStateHelper.GetBool(s, "run_tank_battuta", false);
            _runOneForAll.Checked = SessionStateHelper.GetBool(s, "run_tank_one_for_all", false);
            _runGambit.Checked = SessionStateHelper.GetBool(s, "run_tank_gambit", false);
            _runRayke.Checked = SessionStateHelper.GetBool(s, "run_tank_rayke", false);
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
            var meta = _sessionMetaBySid.TryGetValue(sid, out var m) ? m : null;
            var mainJob = (meta?.Job ?? SessionStateHelper.GetString(s, "job", "")).ToUpperInvariant();
            var subJob = (meta?.SubJob ?? SessionStateHelper.GetString(s, "sub_job", "")).ToUpperInvariant();
            var corVisible = string.Equals(mainJob, "COR", StringComparison.Ordinal) || string.Equals(subJob, "COR", StringComparison.Ordinal);
            EnsureCorTabVisibility(corVisible);
            if (corVisible)
            {
                ApplyCorRollFromSnapshot(_corRoll1Combo, SessionStateHelper.GetString(s, "cor_roll_1"));
                ApplyCorRollFromSnapshot(_corRoll2Combo, SessionStateHelper.GetString(s, "cor_roll_2"));
                var subCorOnly = !string.Equals(mainJob, "COR", StringComparison.Ordinal) && string.Equals(subJob, "COR", StringComparison.Ordinal);
                _corRoll1Combo.Enabled = true;
                _corRoll2Combo.Enabled = !subCorOnly;
                var crookedSlot = SessionStateHelper.GetString(s, "cor_crooked_roll_slot", "0");
                _corCrookedRoll1.Enabled = !subCorOnly;
                _corCrookedRoll2.Enabled = !subCorOnly;
                _corCrookedRoll1.Checked = !subCorOnly && crookedSlot == "1";
                _corCrookedRoll2.Checked = !subCorOnly && crookedSlot == "2";
                _corElevens.Enabled = true;
                _corLuzafRangeOverride.Enabled = true;
                _corElevens.Checked = SessionStateHelper.GetBool(s, "cor_elevens", false);
                _corLuzafRangeOverride.Checked = SessionStateHelper.GetBool(s, "cor_luzaf_range_override", false);
                var selectedNames = SessionStateHelper.SplitOptions(s.TryGetProperty("cor_roll_range_selected", out var crs) ? crs : default);
                RenderCorRangePartyChecks(sid, selectedNames);
            }
            var brdVisible = string.Equals(mainJob, "BRD", StringComparison.Ordinal) || string.Equals(subJob, "BRD", StringComparison.Ordinal);
            EnsureBrdTabVisibility(brdVisible);
            if (brdVisible)
            {
                _brdEnabled.Checked = SessionStateHelper.GetBool(s, "brd_maintenance_enabled", false);
                ApplyBrdList(_brdSongList, SessionStateHelper.GetString(s, "brd_songs"));
                ApplyBrdList(_brdDummyList, SessionStateHelper.GetString(s, "brd_dummy_songs"));
                _brdUseNitro.Checked = SessionStateHelper.GetBool(s, "brd_use_nitro", false);
				_brdUseSoulVoice.Checked = SessionStateHelper.GetBool(s, "brd_use_soul_voice", false);
                _brdUseClarion.Checked = SessionStateHelper.GetBool(s, "brd_use_clarion_call", false);
                _brdUseMarcato.Checked = SessionStateHelper.GetBool(s, "brd_use_marcato", false);
                RefreshBrdMarcatoOptions(SessionStateHelper.GetString(s, "brd_marcato_song"));
				ApplyBrdRecoveryRange(s);
				_brdRepositionForPartySongs.Checked = SessionStateHelper.GetBool(s, "brd_reposition_for_party_songs", false);
				_brdRecoveryIgnoreNames.Text = SessionStateHelper.GetString(s, "brd_recovery_ignore_names");
				_brdTargetedSongs.Text = SessionStateHelper.GetString(s, "brd_targeted_songs");
                var subBrdOnly = !string.Equals(mainJob, "BRD", StringComparison.Ordinal) && string.Equals(subJob, "BRD", StringComparison.Ordinal);
                _brdUseNitro.Enabled = !subBrdOnly;
				_brdUseSoulVoice.Enabled = !subBrdOnly;
                _brdUseClarion.Enabled = !subBrdOnly;
                _brdUseMarcato.Enabled = !subBrdOnly;
                _brdMarcatoSong.Enabled = !subBrdOnly && _brdUseMarcato.Checked;
				_brdTargetedSongs.Enabled = !subBrdOnly;
				EnsureOptionsHydrated(sid);
            }
            var geoVisible = string.Equals(mainJob, "GEO", StringComparison.Ordinal)
                || string.Equals(subJob, "GEO", StringComparison.Ordinal);
            EnsureGeoTabVisibility(geoVisible);
            var summonerVisible = string.Equals(mainJob, "SMN", StringComparison.Ordinal)
                || string.Equals(subJob, "SMN", StringComparison.Ordinal);
            EnsureSummonerTabVisibility(summonerVisible);
            var puppetmasterVisible = string.Equals(mainJob, "PUP", StringComparison.Ordinal);
            EnsurePuppetmasterTabVisibility(puppetmasterVisible);
            var scholarVisible = string.Equals(mainJob, "SCH", StringComparison.Ordinal);
            EnsureScholarTabVisibility(scholarVisible);
            ApplyGeoPullFromSnapshot(s);
            ApplySummonerFromSnapshot(s);
            ApplyPuppetmasterFromSnapshot(s);
            ApplyScholarFromSnapshot(s);
            _reactionEnabled.Checked = SessionStateHelper.GetBool(s, "reaction_enabled", false);
            ApplyReactionRulesFromSnapshot(s);

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
                    cb.Checked = SessionStateHelper.GetBool(s, key, string.Equals(key, "auto_engage", StringComparison.Ordinal));
                }
            }

            RenderAuxLists(s);
            UpdateFormationUiState();
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
        var hasResurrection = s.TryGetProperty("resurrection_options", out var rso) && rso.ValueKind == JsonValueKind.String;
        var hasCorRolls = s.TryGetProperty("cor_roll_options", out var cro) && cro.ValueKind == JsonValueKind.String;
        var hasBrdSongs = s.TryGetProperty("brd_song_options", out var bso) && bso.ValueKind == JsonValueKind.String;
        var hasPartyOpts = s.TryGetProperty("party_options", out var po) && po.ValueKind == JsonValueKind.String;
        if (!hasAbility && !hasWs && !hasPullJa && !hasPullSpell && !hasResurrection && !hasCorRolls && !hasBrdSongs && !hasPartyOpts)
        {
            return;
        }

        var abilityOpts = SessionStateHelper.SplitOptions(hasAbility ? ao : default);
        var wsOpts = SessionStateHelper.SplitOptions(hasWs ? wso : default);
        var pullJaOpts = SessionStateHelper.SplitOptions(hasPullJa ? pjo : default);
        var pullSpellOpts = SessionStateHelper.SplitOptions(hasPullSpell ? pso : default);
        var resurrectionOpts = SessionStateHelper.SplitOptions(hasResurrection ? rso : default);
        var corRollOpts = SessionStateHelper.SplitOptions(hasCorRolls ? cro : default);
        var brdSongOpts = SessionStateHelper.SplitOptions(hasBrdSongs ? bso : default);
        var partyOpts = CurrentSelectablePartyNameOptions(SessionStateHelper.SplitOptions(hasPartyOpts ? po : default));
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
                var wsDisplay = ComboBoxOptionUpdater.BuildDisplayOptions(wsOpts, wsText);
                if (ComboBoxOptionUpdater.ReplaceItemsPreservingTextIfChanged(_wsCombo, wsDisplay, wsText))
                {
                    changed = true;
                }

                var amText = (_aftermathCombo.Text ?? "").Trim();
                var amDisplay = ComboBoxOptionUpdater.BuildDisplayOptions(wsOpts, amText);
                if (ComboBoxOptionUpdater.ReplaceItemsPreservingTextIfChanged(_aftermathCombo, amDisplay, amText))
                {
                    changed = true;
                }
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
                RefreshKeiSpellOptions();
                UpdateEncounterUiState();
                RefreshMagicBurstSpellOptions();
                RefreshReactionActionSpellOptions();
                changed = true;
            }
            if (hasResurrection && !SequenceEqualOrdinal(_defResurrectionOptions, resurrectionOpts))
            {
                _defResurrectionOptions.Clear();
                _defResurrectionOptions.AddRange(resurrectionOpts);
                RefreshDefResurrectionOptions();
                changed = true;
            }
            if (hasCorRolls && !SequenceEqualOrdinal(_corRollOptions, corRollOpts))
            {
                _corRollOptions.Clear();
                _corRollOptions.AddRange(corRollOpts);
                EnsureCorRollOptions(_corRoll1Combo);
                EnsureCorRollOptions(_corRoll2Combo);
                changed = true;
            }

            _sleepMaxTargetRange.Enabled = _boolChecks.TryGetValue("sleep", out var sleepCheck) && sleepCheck.Checked;
            if (hasBrdSongs && !SequenceEqualOrdinal(_brdSongOptions, brdSongOpts))
            {
                _brdSongOptions.Clear();
                _brdSongOptions.AddRange(brdSongOpts);
                RefreshBrdSongPickOptions(_brdSongCombo);
                RefreshBrdSongPickOptions(_brdDummyCombo);
                changed = true;
            }
            if (hasPartyOpts
                && (!SequenceEqualOrdinal(_corPartyOptions, partyOpts)
                    || !SequenceEqualOrdinal(_partyOptions, partyOpts)))
            {
                _corPartyOptions.Clear();
                _corPartyOptions.AddRange(partyOpts);
                _partyOptions.Clear();
                _partyOptions.AddRange(partyOpts);
                var partnerOpts = _partyOptions.Count > 0
                    ? new List<string>(_partyOptions)
                    : SessionStateHelper.SplitOptions(s.TryGetProperty("partner_options", out var po2) ? po2 : default);
                var pullerOpts = SessionStateHelper.SplitOptions(s.TryGetProperty("puller_options", out var plo2) ? plo2 : default);
                if (pullerOpts.Count == 0)
                {
                    pullerOpts = new List<string>(partnerOpts);
                }
                var snapPuller = NormalizePartyName(SessionStateHelper.GetString(s, "puller_selected"));
                var snapFightLeader = NormalizePartyName(SessionStateHelper.GetString(s, "fight_leader_selected"));
                var snapPartyFollow = NormalizePartyName(SessionStateHelper.GetString(s, "party_follow_selected"));
                var keepPuller = SelectedPartyName(_pullerCombo);
                var keepFightLeader = SelectedPartyName(_fightLeaderCombo);
                var keepPartyFollow = SelectedPartyName(_partyFollowCombo);
				var keepNyzulCoordinator = SelectedPartyName(_nyzulCoordinatorCombo);
				var keepNyzulAnchor = SelectedPartyName(_nyzulAnchorCombo);
				var keepNyzulParker = SelectedPartyName(_nyzulParkerCombo);
                var keepKeiDealer = SelectedPartyName(_keiElementalDealer);
                var keepFormationTank = SelectedPartyName(_formationTankName);
                var keepFormationAnchor = SelectedPartyName(_formationAnchorMember);
                var keepFormationAxis = SelectedPartyName(_formationAxisMember);
                var keepFormationRequired = SelectedFormationRequiredPartyNames();
                if (string.IsNullOrWhiteSpace(snapPuller) && !string.IsNullOrWhiteSpace(keepPuller))
                {
                    snapPuller = keepPuller;
                }
                if (string.IsNullOrWhiteSpace(snapFightLeader) && !string.IsNullOrWhiteSpace(keepFightLeader))
                {
                    snapFightLeader = keepFightLeader;
                }
                if (string.IsNullOrWhiteSpace(snapPartyFollow) && !string.IsNullOrWhiteSpace(keepPartyFollow))
                {
                    snapPartyFollow = keepPartyFollow;
                }
                BindPartyCombo(_pullerCombo, pullerOpts, snapPuller);
                BindPartyCombo(_fightLeaderCombo, partnerOpts, snapFightLeader);
                BindPartyCombo(_partyFollowCombo, partnerOpts, snapPartyFollow);
				BindPartyCombo(_nyzulCoordinatorCombo, partnerOpts, keepNyzulCoordinator);
				BindPartyCombo(_nyzulAnchorCombo, partnerOpts, keepNyzulAnchor);
				BindPartyCombo(_nyzulParkerCombo, partnerOpts, keepNyzulParker);
                BindPartyCombo(_keiElementalDealer, partnerOpts, keepKeiDealer);
                BindFormationPartyControls(
                    partnerOpts,
                    keepFormationTank,
                    keepFormationAnchor,
                    keepFormationAxis,
                    keepFormationRequired
                );
                UpdatePartyFollowModeWarning(sid);
                var selectedNames = SessionStateHelper.SplitOptions(s.TryGetProperty("cor_roll_range_selected", out var crs2) ? crs2 : default);
                RenderCorRangePartyChecks(sid, selectedNames);
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
        if (hasWs)
        {
            if (!string.IsNullOrWhiteSpace(job))
            {
                var subJob = meta?.SubJob ?? SessionStateHelper.GetString(s, "sub_job", "");
                OptionsRequestGate.Complete(
                    _optionsHydratedJobBySid,
                    _optionsRequestInFlightBySid,
                    sid,
                    $"{job}/{subJob}"
                );
            }
            else
            {
                _optionsRequestInFlightBySid.Remove(sid);
            }
        }
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
        UpdateAbilityListLayout();
        var healerOn = _boolChecks.TryGetValue("defensive_enabled", out var hb) && hb.Checked;
        _grpHealer.Title = healerOn ? "Defensive" : "Defensive (inactive)";
        var dim = SystemColors.GrayText;
        var bright = SystemColors.ControlText;
        foreach (var key in new[]
                 {
                     "defensive_cure_enabled",
                     "defensive_curaga_enabled",
                     "defensive_waltz_enabled",
                     "defensive_doom_water",
                     "def_charm_sleeper_enabled",
                     "def_sleep_waker_enabled",
                     "def_remove_enemy_buffs",
                     "defensive_na_enabled",
                     "defensive_na_limit_enabled",
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
        var naEnabled = _boolChecks.TryGetValue("defensive_na_enabled", out var na) && na.Checked;
        var limitEnabled = _boolChecks.TryGetValue("defensive_na_limit_enabled", out var limit) && limit.Checked;
        _defNaPriority.Enabled = healerOn && naEnabled && limitEnabled;
        _defCuragaMinTargets.Enabled = healerOn && _boolChecks.TryGetValue("defensive_curaga_enabled", out var curaga) && curaga.Checked;
        var waltzEnabled = healerOn && _boolChecks.TryGetValue("defensive_waltz_enabled", out var waltz) && waltz.Checked;
        _defWaltzTpReserve.Enabled = waltzEnabled;
        _defDivineWaltzMinTargets.Enabled = waltzEnabled;
    }

    private void UpdateAbilityListLayout()
    {
        var hasWorkingList = _chkAbility.Checked && _abilityList.Items.Count > 0;
        _abilityList.Height = hasWorkingList ? 96 : 44;
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
            UpdateAbilityListLayout();
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
            _ignoreList.Items.Add($"{FormatPartyDisplayName(name)} [{id}]");
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
            _partnerList.Items.Add($"{FormatPartyDisplayName(name)} [{id}]");
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

    private void RenderNoSkillchainTargetList(JsonElement s)
    {
        _noSkillchainTargetCurrent.Enabled = true;
        var newRows = SessionStateHelper.ParseIgnoreEntriesFrom(s, "no_skillchain_target_entries");
        if (newRows.SequenceEqual(_noSkillchainTargetRows) && _noSkillchainTargetList.Items.Count == newRows.Count)
        {
            return;
        }

        _noSkillchainTargetRows = newRows;
        RebindNoSkillchainTargetListUi();
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

    private void RenderSleepSpellList(JsonElement s)
    {
        var newRows = SessionStateHelper.ParseIgnoreEntriesFrom(s, "sleep_spell_entries");
        if (newRows.Count == 0)
        {
            var legacyPrimary = SessionStateHelper.GetString(s, "sleepspell");
            if (!string.IsNullOrWhiteSpace(legacyPrimary))
            {
                newRows = [(1, legacyPrimary)];
            }
        }

        if (newRows.SequenceEqual(_sleepSpellRows) && _sleepSpellList.Items.Count == newRows.Count)
        {
            return;
        }

        string? preserved = null;
        if (_sleepSpellList.SelectedIndex >= 0 && _sleepSpellRows.Count > 0 && _sleepSpellList.SelectedIndex < _sleepSpellRows.Count)
        {
            preserved = _sleepSpellRows[_sleepSpellList.SelectedIndex].Name;
        }

        _sleepSpellRows = newRows;
        RebindSleepSpellListUi();

        if (preserved != null)
        {
            for (var i = 0; i < _sleepSpellRows.Count; i++)
            {
                if (_sleepSpellRows[i].Name == preserved)
                {
                    _sleepSpellList.SelectedIndex = i;
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
			var campSource = string.Equals(_pullerLeashSource.SelectedItem?.ToString(), "Camp", StringComparison.Ordinal);
			_pullerLeashSource.Enabled = val;
			_pullerCombo.Enabled = val && !campSource;
            _pullerEngageRange.Enabled = val;
			_campSet.Enabled = val && campSource;
			_campClear.Enabled = val && campSource;
            var ps = SelectedPartyName(_pullerCombo);
            if (val && !string.IsNullOrEmpty(ps) && !ComboContainsPartyName(_pullerCombo, ps))
            {
                _pullerCombo.SelectedIndex = 0;
                OnPullerSelected();
            }
        }

        if (key == "sleep")
        {
            _sleepMaxTargetRange.Enabled = val;
        }

        if (key == "fight_leader")
        {
            _fightLeaderCombo.Enabled = val;
            var fs = SelectedPartyName(_fightLeaderCombo);
            if (val && !string.IsNullOrEmpty(fs) && !ComboContainsPartyName(_fightLeaderCombo, fs))
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
            var pfs = SelectedPartyName(_partyFollowCombo);
            if (val && !string.IsNullOrEmpty(pfs) && !ComboContainsPartyName(_partyFollowCombo, pfs))
            {
                _partyFollowCombo.SelectedIndex = 0;
                OnPartyFollowSelected();
            }
            if (!string.IsNullOrWhiteSpace(sid))
            {
                UpdatePartyFollowModeWarning(sid);
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

    private static string WsModeUiToRuntime(string? ui)
    {
        return string.Equals(ui, "Primary Only (No SC)", StringComparison.Ordinal)
            ? "primary_no_sc"
            : "smart";
    }

    private static string WsModeRuntimeToUi(string? runtime)
    {
        return string.Equals(runtime, "primary_no_sc", StringComparison.OrdinalIgnoreCase)
            ? "Primary Only (No SC)"
            : "Smart";
    }

    private static string SkillchainTargetUiToRuntime(string? value)
    {
        var normalized = (value ?? "Auto").Trim().ToLowerInvariant();
        return normalized switch
        {
            "auto" or "compression" or "liquefaction" or "induration" or "reverberation"
                or "transfixion" or "scission" or "detonation" or "impaction"
                or "gravitation" or "fragmentation" or "distortion" or "fusion"
                or "light" or "darkness" or "radiance" or "umbra" => normalized,
            _ => throw new InvalidOperationException($"unsupported skillchain target: {value}"),
        };
    }

    private static string SkillchainTargetRuntimeToUi(string? value)
    {
        var normalized = SkillchainTargetUiToRuntime(value);
        return normalized == "auto"
            ? "Auto"
            : char.ToUpperInvariant(normalized[0]) + normalized[1..];
    }

    private void OnSkillchainTargetSelected()
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
        var target = SkillchainTargetUiToRuntime(_skillchainTargetCombo.SelectedItem?.ToString());
        Forward(sid, new Dictionary<string, object?>
        {
            ["op"] = "set",
            ["path"] = "skillchain_target",
            ["value"] = target,
        });
        CaptureWorkingProfileFromUi(sid);
    }

    private void OnWsModeSelected()
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

        var mode = WsModeUiToRuntime(_wsModeCombo.SelectedItem?.ToString() ?? "Smart");
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "ws_mode", ["value"] = mode });
    }

    private void OnWsMinimumTpChanged()
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

        Forward(sid, new Dictionary<string, object?>
        {
            ["op"] = "set",
            ["path"] = "weaponskill_min_tp",
            ["value"] = decimal.ToInt32(_wsMinimumTp.Value),
        });
    }

    private static decimal ReadWeaponskillMinimumTp(JsonElement state)
    {
        if (!state.TryGetProperty("weaponskill_min_tp", out var raw))
        {
            return 1000;
        }
        if (raw.ValueKind != JsonValueKind.Number || !raw.TryGetInt32(out var value))
        {
            throw new InvalidDataException("weaponskill_min_tp must be an integer from 1000 to 3000.");
        }
        if (value < 1000 || value > 3000)
        {
            throw new InvalidDataException("weaponskill_min_tp must be an integer from 1000 to 3000.");
        }
        return value;
    }

    private void OnWsAllowAoeChanged()
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

        Forward(sid, new Dictionary<string, object?>
        {
            ["op"] = "set",
            ["path"] = "weaponskill_allow_aoe",
            ["value"] = _chkWsAllowAoe.Checked,
        });
    }

    private void OnFastSkillchainChanged()
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

        Forward(sid, new Dictionary<string, object?>
        {
            ["op"] = "set",
            ["path"] = "fast_skillchain",
            ["value"] = _chkFastSkillchain.Checked,
        });
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
        var selected = combo.SelectedItem?.ToString() ?? combo.Text ?? "";
        var src = _corRollOptions.Count > 0 ? _corRollOptions : HubUiConstants.CorRollOptions.ToList();
        var next = BuildCorRollOptions(src, selected);
        var cur = combo.Items.Cast<object>().Select(x => x?.ToString() ?? "").ToList();
        if (SequenceEqualOrdinal(cur, next))
        {
            return;
        }
        combo.Items.Clear();
        foreach (var roll in next)
        {
            combo.Items.Add(roll);
        }
        combo.SelectedIndex = next.FindIndex(value => string.Equals(value, selected, StringComparison.Ordinal));
    }

    internal static List<string> BuildCorRollOptions(IReadOnlyList<string> options, string selected)
    {
        var next = new List<string> { "" };
        next.AddRange(options);
        if (!string.IsNullOrEmpty(selected) && !next.Contains(selected, StringComparer.Ordinal))
        {
            next.Insert(1, selected);
        }
        return next;
    }

    private void EnsureCorTabVisibility(bool shouldShow)
    {
        if (_settingsTabs is null || _tabCor is null)
        {
            return;
        }

        var hasCorTab = _settingsTabs.TabPages.Contains(_tabCor);
        if (shouldShow && !hasCorTab)
        {
            _settingsTabs.TabPages.Add(_tabCor);
        }
        else if (!shouldShow && hasCorTab)
        {
            var wasSelected = ReferenceEquals(_settingsTabs.SelectedTab, _tabCor);
            _settingsTabs.TabPages.Remove(_tabCor);
            if (wasSelected && _settingsTabs.TabPages.Count > 0)
            {
                _settingsTabs.SelectedIndex = 0;
            }
        }
    }

    private void EnsureGeoTabVisibility(bool shouldShow)
    {
        EnsureJobTabVisibility(_tabGeo, shouldShow);
    }

    private void EnsureSummonerTabVisibility(bool shouldShow)
    {
        EnsureJobTabVisibility(_tabSummoner, shouldShow);
    }

    private void EnsureScholarTabVisibility(bool shouldShow)
    {
        EnsureJobTabVisibility(_tabScholar, shouldShow);
    }

    private void EnsureJobTabVisibility(TabPage tab, bool shouldShow)
    {
        if (_settingsTabs is null || tab is null)
        {
            return;
        }
        var hasTab = _settingsTabs.TabPages.Contains(tab);
        if (shouldShow && !hasTab)
        {
            _settingsTabs.TabPages.Add(tab);
            return;
        }
        if (!shouldShow && hasTab)
        {
            var wasSelected = ReferenceEquals(_settingsTabs.SelectedTab, tab);
            _settingsTabs.TabPages.Remove(tab);
            if (wasSelected && _settingsTabs.TabPages.Count > 0)
            {
                _settingsTabs.SelectedIndex = 0;
            }
        }
    }

    private static void BindSummonerActionCombo(
        ComboBox combo,
        IEnumerable<SummonerActionCapability> actions,
        string selected
    )
    {
        var names = actions.Select(action => action.Name).ToList();
        if (selected.Length != 0 && !names.Contains(selected, StringComparer.Ordinal))
        {
            names.Insert(0, selected);
        }
        names.Insert(0, "");
        combo.Items.Clear();
        foreach (var name in names)
        {
            combo.Items.Add(name);
        }
        combo.SelectedIndex = names.FindIndex(name => string.Equals(name, selected, StringComparison.Ordinal));
    }

	private sealed record SummonerWardListItem(string Name, string Avatar)
	{
		public override string ToString() => Avatar.Length == 0 ? Name : $"{Avatar} — {Name}";
	}

	private void BindSummonerWardList(IEnumerable<string> selectedActions)
	{
		var selected = selectedActions
			.Where(name => !string.IsNullOrWhiteSpace(name))
			.Distinct(StringComparer.Ordinal)
			.ToList();
		var supported = SummonerCapabilities.Wards
			.Select(action => new SummonerWardListItem(action.Name, action.Avatar))
			.ToList();
		foreach (var name in selected)
		{
			if (SummonerCapabilities.FindWard(name) is null)
			{
				supported.Insert(0, new SummonerWardListItem(name, ""));
			}
		}
		_summonerWardActions.Items.Clear();
		foreach (var item in supported)
		{
			_summonerWardActions.Items.Add(item, selected.Contains(item.Name, StringComparer.Ordinal));
		}
	}

	private List<string> SelectedSummonerWardActions()
	{
		return _summonerWardActions.CheckedItems
			.Cast<SummonerWardListItem>()
			.Select(item => item.Name)
			.Distinct(StringComparer.Ordinal)
			.ToList();
	}

    private void BindSummonerAvatarCombo(string selected)
    {
        var names = SummonerCapabilities.Avatars.Select(avatar => avatar.Name).ToList();
        if (selected.Length != 0 && !names.Contains(selected, StringComparer.Ordinal))
        {
            names.Insert(0, selected);
        }
        names.Insert(0, "");
        _summonerAvatar.Items.Clear();
        foreach (var name in names)
        {
            _summonerAvatar.Items.Add(name);
        }
        _summonerAvatar.SelectedIndex = names.FindIndex(
            name => string.Equals(name, selected, StringComparison.Ordinal)
        );
    }

    private void ApplySummonerFromSnapshot(JsonElement snapshot)
    {
        _summonerEnabled.Checked = SessionStateHelper.GetBool(snapshot, "summoner_enabled", false);
        var avatarName = SessionStateHelper.GetString(snapshot, "summoner_avatar");
        BindSummonerAvatarCombo(avatarName);
        _summonerAvatarFavor.Checked = SessionStateHelper.GetBool(snapshot, "summoner_avatar_favor", false);
        _summonerWardEnabled.Checked = SessionStateHelper.GetBool(snapshot, "summoner_ward_enabled", false);
        _summonerEngage.Checked = SessionStateHelper.GetBool(
            snapshot,
            "summoner_engage_on_combat_start",
            false
        );
        _summonerRageEnabled.Checked = SessionStateHelper.GetBool(snapshot, "summoner_rage_enabled", false);

		var wardActions = SessionStateHelper.SplitOptions(
			snapshot.TryGetProperty("summoner_ward_actions", out var wardActionsNode)
				? wardActionsNode
				: default
		);
		var legacyWardAction = SessionStateHelper.GetString(snapshot, "summoner_ward_action");
		if (wardActions.Count == 0 && legacyWardAction.Length != 0)
		{
			wardActions.Add(legacyWardAction);
		}
		BindSummonerWardList(wardActions);
		var avatar = SummonerCapabilities.FindAvatar(avatarName);
        BindSummonerActionCombo(
            _summonerRageAction,
            avatar is null ? [] : avatar.Rages,
            SessionStateHelper.GetString(snapshot, "summoner_rage_action")
        );
        var usage = SessionStateHelper.GetString(snapshot, "summoner_rage_usage", "on_cooldown");
        if (!string.Equals(usage, "on_cooldown", StringComparison.Ordinal))
        {
            throw new InvalidDataException($"Unsupported Summoner Rage usage policy '{usage}'.");
        }
        _summonerRageTargetHppAboveEnabled.Checked = ReadOptionalSummonerGateEnabled(
            snapshot,
            "summoner_rage_target_hpp_above_enabled"
        );
        _summonerRageTargetHppAbove.Value = ReadOptionalSummonerGateThreshold(
            snapshot,
            "summoner_rage_target_hpp_above",
            50,
            99
        );
        _summonerRagePetTpAboveEnabled.Checked = ReadOptionalSummonerGateEnabled(
            snapshot,
            "summoner_rage_pet_tp_above_enabled"
        );
        _summonerRagePetTpAbove.Value = ReadOptionalSummonerGateThreshold(
            snapshot,
            "summoner_rage_pet_tp_above",
            2000,
            2999
        );
        UpdateSummonerUiState();
    }

    private static int ReadOptionalSummonerGateThreshold(
        JsonElement snapshot,
        string key,
        int defaultValue,
        int maximum
    )
    {
        if (!snapshot.TryGetProperty(key, out var value))
        {
            return defaultValue;
        }
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var threshold))
        {
            throw new InvalidDataException($"{key} must be an integer.");
        }
        if (threshold < 0 || threshold > maximum)
        {
            throw new InvalidDataException($"{key} must be from 0 to {maximum}.");
        }
        return threshold;
    }

    private static bool ReadOptionalSummonerGateEnabled(JsonElement snapshot, string key)
    {
        if (!snapshot.TryGetProperty(key, out var value))
        {
            return false;
        }
        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => throw new InvalidDataException($"{key} must be boolean."),
        };
    }

    private void OnSummonerAvatarChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        var rage = _summonerRageAction.SelectedItem?.ToString() ?? "";
        var avatarName = _summonerAvatar.SelectedItem?.ToString() ?? "";
        var avatar = SummonerCapabilities.FindAvatar(avatarName);
        var wasSuppressed = _suppressEvents;
        _suppressEvents = true;
        try
        {
            BindSummonerActionCombo(_summonerRageAction, avatar is null ? [] : avatar.Rages, rage);
        }
        finally
        {
            _suppressEvents = wasSuppressed;
        }
        UpdateSummonerUiState();
        var sid = RequireSelectedSid();
        if (sid is not null)
        {
            CaptureWorkingProfileFromUi(sid);
        }
    }

    private void OnSummonerSettingChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        UpdateSummonerUiState();
        var sid = RequireSelectedSid();
        if (sid is not null)
        {
            CaptureWorkingProfileFromUi(sid);
        }
    }

    private void OnSummonerActionChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        UpdateSummonerUiState();
        var sid = RequireSelectedSid();
        if (sid is not null)
        {
            CaptureWorkingProfileFromUi(sid);
        }
    }

	private void OnSummonerWardItemCheck()
	{
		if (_suppressEvents || !IsHandleCreated)
		{
			return;
		}
		BeginInvoke(
			() =>
			{
				if (!IsDisposed)
				{
					OnSummonerActionChanged();
				}
			}
		);
	}

    private void UpdateSummonerUiState()
    {
        var enabled = _summonerEnabled.Checked;
        var avatarName = _summonerAvatar.SelectedItem?.ToString() ?? "";
        var avatarValid = SummonerCapabilities.FindAvatar(avatarName) is not null;
		var wardActions = SelectedSummonerWardActions();
        var rageAction = _summonerRageAction.SelectedItem?.ToString() ?? "";
        var wardValid = !_summonerWardEnabled.Checked
			|| (wardActions.Count > 0 && wardActions.All(action => SummonerCapabilities.FindWard(action) is not null));
        var rageValid = !_summonerRageEnabled.Checked
            || SummonerCapabilities.IsCompatible(avatarName, "rage", rageAction);

        _summonerAvatar.Enabled = enabled;
        _summonerAvatarFavor.Enabled = enabled && avatarValid;
        _summonerWardEnabled.Enabled = enabled && avatarValid;
		_summonerWardActions.Enabled = enabled && avatarValid && _summonerWardEnabled.Checked;
        _summonerEngage.Enabled = enabled && avatarValid;
        _summonerRageEnabled.Enabled = enabled && avatarValid;
        _summonerRageAction.Enabled = enabled && avatarValid && _summonerRageEnabled.Checked;
        var rageGateControlsEnabled = enabled && avatarValid && _summonerRageEnabled.Checked;
        _summonerRageTargetHppAboveEnabled.Enabled = rageGateControlsEnabled;
        _summonerRageTargetHppAbove.Enabled =
            rageGateControlsEnabled && _summonerRageTargetHppAboveEnabled.Checked;
        _summonerRagePetTpAboveEnabled.Enabled = rageGateControlsEnabled;
        _summonerRagePetTpAbove.Enabled =
            rageGateControlsEnabled && _summonerRagePetTpAboveEnabled.Checked;

        if (!enabled)
        {
            _summonerValidation.ForeColor = SystemColors.GrayText;
            _summonerValidation.Text = "Summoner automation is disabled.";
        }
        else if (!avatarValid)
        {
            _summonerValidation.ForeColor = Color.Firebrick;
            _summonerValidation.Text = avatarName.Length == 0
				? "A primary avatar is required."
				: $"Primary avatar '{avatarName}' is not supported.";
        }
        else if (!wardValid || !rageValid)
        {
            var issues = new List<string>();
            if (!wardValid)
            {
				var unsupported = wardActions.FirstOrDefault(action => SummonerCapabilities.FindWard(action) is null);
				issues.Add(wardActions.Count == 0
					? "Select at least one Ward action."
					: $"Ward '{unsupported}' is not supported.");
            }
            if (!rageValid)
            {
                issues.Add(rageAction.Length == 0
                    ? "Select a Rage action."
                    : $"Rage '{rageAction}' is incompatible with {avatarName}.");
            }
            _summonerValidation.ForeColor = Color.DarkGoldenrod;
            _summonerValidation.Text = string.Join(" ", issues);
        }
        else
        {
            _summonerValidation.ForeColor = Color.DarkGreen;
            _summonerValidation.Text = $"Summoner configuration is valid for {avatarName}.";
        }
    }

    private static bool ReadOptionalScholarBool(JsonElement snapshot, string key, bool defaultValue)
    {
        if (!snapshot.TryGetProperty(key, out var value))
        {
            return defaultValue;
        }
        return value.ValueKind switch
        {
            JsonValueKind.True => true,
            JsonValueKind.False => false,
            _ => throw new InvalidDataException($"{key} must be boolean."),
        };
    }

    private static decimal ReadOptionalScholarInteger(
        JsonElement snapshot,
        string key,
        int defaultValue,
        int minimum,
        int maximum
    )
    {
        if (!snapshot.TryGetProperty(key, out var value))
        {
            return defaultValue;
        }
        if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var number))
        {
            throw new InvalidDataException($"{key} must be an integer.");
        }
        if (number < minimum || number > maximum)
        {
            throw new InvalidDataException($"{key} must be from {minimum} to {maximum}.");
        }
        return number;
    }

    private void ApplyScholarFromSnapshot(JsonElement snapshot)
    {
        _schEnabled.Checked = ReadOptionalScholarBool(snapshot, "sch_enabled", false);
        _schArtsMinimumCommit.Value = ReadOptionalScholarInteger(
            snapshot,
            "sch_arts_minimum_commit_s",
            12,
            0,
            120
        );
        _schArtsEmergencyOffArtCasts.Checked = ReadOptionalScholarBool(
            snapshot,
            "sch_arts_emergency_off_art_casts",
            true
        );
        _schRegenEnabled.Checked = ReadOptionalScholarBool(snapshot, "sch_regen_enabled", false);
        _schAccessionPerpetuanceSpells.Text = SessionStateHelper.GetString(
            snapshot,
            "sch_accession_perpetuance_spells"
        );
        _schRegenMinimumCoverage.Value = ReadOptionalScholarInteger(
            snapshot,
            "sch_regen_minimum_coverage",
            4,
            1,
            6
        );
        _schRegenRefreshBefore.Value = ReadOptionalScholarInteger(
            snapshot,
            "sch_regen_refresh_before_s",
            25,
            1,
            300
        );
        _schStormsEnabled.Checked = ReadOptionalScholarBool(snapshot, "sch_storms_enabled", false);
        _schStormAssignments.Text = SessionStateHelper.GetString(snapshot, "sch_storm_assignments");
        _schStormsRefreshBefore.Value = ReadOptionalScholarInteger(
            snapshot,
            "sch_storms_refresh_before_s",
            30,
            1,
            300
        );
        _schSublimationEnabled.Checked = ReadOptionalScholarBool(
            snapshot,
            "sch_sublimation_enabled",
            false
        );
        _schSublimationReleaseMpp.Value = ReadOptionalScholarInteger(
            snapshot,
            "sch_sublimation_release_when_mpp_at_most",
            45,
            0,
            100
        );
        _schSublimationReleaseComplete.Checked = ReadOptionalScholarBool(
            snapshot,
            "sch_sublimation_release_when_complete",
            false
        );
        _schSublimationMinimumHpp.Value = ReadOptionalScholarInteger(
            snapshot,
            "sch_sublimation_minimum_hpp_to_activate",
            75,
            1,
            100
        );
        _schAccessionCureEnabled.Checked = ReadOptionalScholarBool(
            snapshot, "sch_accession_cure_enabled", false
        );
        _schAccessionStatusRemovalEnabled.Checked = ReadOptionalScholarBool(
            snapshot, "sch_accession_status_removal_enabled", false
        );
        _schRaptureEnabled.Checked = ReadOptionalScholarBool(
            snapshot, "sch_rapture_enabled", false
        );
        _schPenuryEnabled.Checked = ReadOptionalScholarBool(
            snapshot, "sch_penury_enabled", false
        );
        UpdateScholarUiState();
    }

    private void OnScholarSettingChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        UpdateScholarUiState();
        var sid = RequireSelectedSid();
        if (sid is not null)
        {
            CaptureWorkingProfileFromUi(sid);
        }
    }

    private void UpdateScholarUiState()
    {
        var enabled = _schEnabled.Checked;
        _schArtsMinimumCommit.Enabled = enabled;
        _schArtsEmergencyOffArtCasts.Enabled = enabled;
        _schRegenEnabled.Enabled = enabled;
        _schAccessionPerpetuanceSpells.Enabled = enabled && _schRegenEnabled.Checked;
        _schRegenMinimumCoverage.Enabled = enabled && _schRegenEnabled.Checked;
        _schRegenRefreshBefore.Enabled = enabled && _schRegenEnabled.Checked;
        _schStormsEnabled.Enabled = enabled;
        _schStormAssignments.Enabled = enabled && _schStormsEnabled.Checked;
        _schStormsRefreshBefore.Enabled = enabled && _schStormsEnabled.Checked;
        _schSublimationEnabled.Enabled = enabled;
        _schSublimationReleaseMpp.Enabled = enabled && _schSublimationEnabled.Checked;
        _schSublimationReleaseComplete.Enabled = enabled && _schSublimationEnabled.Checked;
        _schSublimationMinimumHpp.Enabled = enabled && _schSublimationEnabled.Checked;
        _schAccessionCureEnabled.Enabled = enabled;
        _schAccessionStatusRemovalEnabled.Enabled = enabled;
        _schRaptureEnabled.Enabled = enabled;
        _schPenuryEnabled.Enabled = enabled;

        if (!enabled)
        {
            _schValidation.ForeColor = SystemColors.GrayText;
            _schValidation.Text = "Scholar automation is disabled.";
            return;
        }
        try
        {
            StructuredProfileV2Writer.ParseScholarAccessionMaintenanceSpells(
                _schAccessionPerpetuanceSpells.Text.Trim()
            );
            StructuredProfileV2Writer.ParseScholarStormAssignments(_schStormAssignments.Text.Trim());
        }
        catch (InvalidDataException ex)
        {
            _schValidation.ForeColor = Color.Firebrick;
            _schValidation.Text = ex.Message;
            return;
        }
        _schValidation.ForeColor = Color.DarkGreen;
        _schValidation.Text = "Scholar support and group-defense configuration is valid.";
    }

    private void EnsureBrdTabVisibility(bool shouldShow)
    {
        if (_settingsTabs is null || _tabBrd is null)
        {
            return;
        }

        var hasTab = _settingsTabs.TabPages.Contains(_tabBrd);
        if (shouldShow && !hasTab)
        {
            _settingsTabs.TabPages.Add(_tabBrd);
        }
        else if (!shouldShow && hasTab)
        {
            var wasSelected = ReferenceEquals(_settingsTabs.SelectedTab, _tabBrd);
            _settingsTabs.TabPages.Remove(_tabBrd);
            if (wasSelected && _settingsTabs.TabPages.Count > 0)
            {
                _settingsTabs.SelectedIndex = 0;
            }
        }
    }

    private void OnPullerEngageRangeChanged()
    {
        CommitDurableRange(_pullerEngageRange, 6.0);
    }

	private void OnPullerLeashSourceChanged()
	{
		if (_suppressEvents || string.IsNullOrWhiteSpace(_selectedSid))
		{
			return;
		}
		if (_pullerLeashSource.SelectedItem?.ToString() is not ("Player" or "Camp"))
		{
			throw new InvalidOperationException("Puller leash source must be Player or Camp.");
		}
		var campSource = string.Equals(_pullerLeashSource.SelectedItem.ToString(), "Camp", StringComparison.Ordinal);
		_pullerCombo.Enabled = _chkPuller.Checked && !campSource;
		_campSet.Enabled = _chkPuller.Checked && campSource;
		_campClear.Enabled = _chkPuller.Checked && campSource;
		CaptureWorkingProfileFromUi(_selectedSid);
	}

    private void OnSleepMaxTargetRangeChanged()
    {
        CommitDurableRange(_sleepMaxTargetRange, 6.0);
    }

    private void CommitDurableRange(TextBox control, double defaultValue)
    {
        if (_suppressEvents || string.IsNullOrWhiteSpace(_selectedSid))
        {
            return;
        }

        if (!double.TryParse((control.Text ?? "").Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
        {
            value = defaultValue;
        }
        value = Math.Clamp(value, 0.1, 50.0);
        control.Text = value.ToString("0.###", CultureInfo.InvariantCulture);
        CaptureWorkingProfileFromUi(_selectedSid);
    }

    private static void ApplyBrdList(ListBox list, string raw)
    {
        var incoming = raw.Split('|', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        var current = list.Items.Cast<object>().Select(x => x.ToString() ?? "").ToArray();
        if (current.SequenceEqual(incoming, StringComparer.Ordinal))
        {
            return;
        }
        list.Items.Clear();
        list.Items.AddRange(incoming.Cast<object>().ToArray());
    }

	private void ApplyBrdRecoveryRange(JsonElement snapshot)
	{
		var raw = SessionStateHelper.GetString(snapshot, "brd_recovery_range_yalms", "9.9");
		if (!decimal.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
		{
			throw new InvalidDataException($"BRD recovery range is not numeric: {raw}");
		}
		if (value < _brdRecoveryRangeYalms.Minimum || value > _brdRecoveryRangeYalms.Maximum)
		{
			throw new InvalidDataException($"BRD recovery range is outside 1.0..20.0: {value}");
		}
		_brdRecoveryRangeYalms.Value = value;
	}

    private void RefreshBrdSongPickOptions(ComboBox combo)
    {
        var selected = combo.SelectedItem?.ToString() ?? "";
        combo.Items.Clear();
        combo.Items.AddRange(_brdSongOptions.Cast<object>().ToArray());
        var index = combo.Items.Cast<object>().ToList().FindIndex(x => string.Equals(x?.ToString(), selected, StringComparison.Ordinal));
        combo.SelectedIndex = index >= 0 ? index : (combo.Items.Count > 0 ? 0 : -1);
    }

    private void RefreshBrdMarcatoOptions(string selected = "")
    {
        var wasSuppressed = _suppressEvents;
        _suppressEvents = true;
        try
        {
            if (string.IsNullOrEmpty(selected))
            {
                selected = _brdMarcatoSong.SelectedItem?.ToString() ?? "";
            }
            _brdMarcatoSong.Items.Clear();
            foreach (var item in _brdSongList.Items.Cast<object>().Select(x => x.ToString() ?? ""))
            {
                _brdMarcatoSong.Items.Add(item);
            }
            var index = _brdMarcatoSong.Items.Cast<object>().ToList().FindIndex(x => string.Equals(x?.ToString(), selected, StringComparison.Ordinal));
            _brdMarcatoSong.SelectedIndex = index >= 0 ? index : (_brdMarcatoSong.Items.Count > 0 ? 0 : -1);
            _brdMarcatoSong.Enabled = _brdUseMarcato.Enabled && _brdUseMarcato.Checked;
        }
        finally
        {
            _suppressEvents = wasSuppressed;
        }
    }

    private void OnBrdConfigChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        RefreshBrdMarcatoOptions();
        if (!string.IsNullOrWhiteSpace(_selectedSid))
        {
            CaptureWorkingProfileFromUi(_selectedSid);
        }
    }

    private void OnMagicBurstConfigChanged()
    {
        if (_suppressEvents || string.IsNullOrWhiteSpace(_selectedSid))
        {
  return;
        }
        var sid = _selectedSid;
        UpdateMagicBurstTierUi();
        var mode = MagicBurstModeValue();
        var family = MagicBurstFamilyValue();
        var maxTier = MagicBurstMaxTierValue();
        Forward(sid, new Dictionary<string, object?>
        {
  ["op"] = "set",
  ["path"] = "magic_burst_enabled",
  ["value"] = _magicBurstEnabled.Checked ? "on" : "off",
        });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "magic_burst_mode", ["value"] = mode });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "magic_burst_family", ["value"] = family });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "magic_burst_max_tier", ["value"] = maxTier });
        if (mode == "exact")
        {
  Forward(sid, new Dictionary<string, object?>
  {
      ["op"] = "set",
      ["path"] = "spell",
      ["value"] = (_magicBurstSpell.Text ?? "").Trim(),
  });
        }
        CaptureWorkingProfileFromUi(sid);
    }

    private void RefreshMagicBurstSpellOptions(string? selected = null)
    {
        selected = string.IsNullOrWhiteSpace(selected) ? (_magicBurstSpell.Text ?? "").Trim() : selected.Trim();
        var options = new List<string>(MagicBurstAutoSelections);
        foreach (var spell in _pathPullSpellOptions)
        {
  if (!string.IsNullOrWhiteSpace(spell) && !options.Contains(spell, StringComparer.Ordinal))
  {
      options.Add(spell);
  }
        }
        if (!string.IsNullOrWhiteSpace(selected) && !options.Contains(selected, StringComparer.Ordinal))
        {
  options.Insert(MagicBurstAutoSelections.Length, selected);
        }
        _magicBurstSpell.Items.Clear();
        foreach (var option in options)
        {
  _magicBurstSpell.Items.Add(option);
        }
        var index = options.FindIndex(value => string.Equals(value, selected, StringComparison.Ordinal));
        if (index >= 0)
        {
  _magicBurstSpell.SelectedIndex = index;
        }
        else
        {
  _magicBurstSpell.SelectedIndex = -1;
  _magicBurstSpell.Text = selected;
        }
        UpdateMagicBurstTierUi();
    }

    private void RefreshReactionActionSpellOptions(string? selected = null)
    {
        selected = string.IsNullOrWhiteSpace(selected) ? (_reactionActionName.Text ?? "").Trim() : selected.Trim();
        _reactionActionName.Items.Clear();
        foreach (var spell in _pathPullSpellOptions)
        {
            _reactionActionName.Items.Add(spell);
        }
        _reactionActionName.Text = selected ?? "";
    }

    private void ApplyReactionRulesFromSnapshot(JsonElement snapshot)
    {
        _reactionRules.Clear();
        if (snapshot.TryGetProperty("reaction_rules", out var rules) && rules.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in rules.EnumerateArray())
            {
                if (item.ValueKind != JsonValueKind.Object)
                {
                    continue;
                }
                var trigger = SessionStateHelper.GetString(item, "trigger").Trim();
                var name = SessionStateHelper.GetString(item, "name").Trim();
                var response = SessionStateHelper.GetString(item, "response").Trim();
                var activateEvent = SessionStateHelper.GetString(item, "activate_event").Trim();
                var valid = (trigger == "ability_window" && (response == "turn_away" || response == "run_away" || response == "move_to_range" || response == "use_action"))
                    || (trigger == "enemy_buff" && response == "stop_attacking")
                    || (trigger == "event_window" && (response is "stop_attacking" or "turn_away")
                        && activateEvent is "spell_start" or "ability_start" or "buff_gained");
                double? distance = null;
                string? actionType = null;
                string? actionName = null;
                string? releaseEvent = null;
                string? releaseName = null;
                double? confirmationTimeoutSeconds = null;
                if (response is "run_away" or "move_to_range")
                {
                    if (!item.TryGetProperty("distance", out var distanceNode)
                        || distanceNode.ValueKind != JsonValueKind.Number
                        || !distanceNode.TryGetDouble(out var parsedDistance)
                        || !double.IsFinite(parsedDistance)
                        || parsedDistance <= 0)
                    {
                        throw new InvalidDataException($"{response} reaction requires a positive finite distance");
                    }
                    distance = parsedDistance;
                }
                else if (response == "use_action")
                {
                    actionType = SessionStateHelper.GetString(item, "action_type").Trim();
                    actionName = SessionStateHelper.GetString(item, "action_name").Trim();
                    if (actionType != "spell" || actionName.Length == 0)
                    {
                        throw new InvalidDataException("use_action reaction requires action_type 'spell' and a non-empty action_name");
                    }
                }
                if (trigger == "event_window")
                {
                    releaseEvent = SessionStateHelper.GetString(item, "release_event").Trim();
                    releaseName = SessionStateHelper.GetString(item, "release_name", name).Trim();
                    if (releaseEvent is not ("spell_end" or "ability_end" or "buff_lost") || releaseName.Length == 0)
                    {
                        throw new InvalidDataException("event_window reaction requires a valid release_event and release_name");
                    }
                    if (releaseEvent == "buff_lost")
                    {
                        confirmationTimeoutSeconds = item.TryGetProperty("confirmation_timeout_seconds", out var timeoutNode)
                            && timeoutNode.ValueKind == JsonValueKind.Number
                            && timeoutNode.TryGetDouble(out var parsedTimeout)
                            ? parsedTimeout
                            : 1.5;
                        if (!double.IsFinite(confirmationTimeoutSeconds.Value)
                            || confirmationTimeoutSeconds.Value <= 0
                            || confirmationTimeoutSeconds.Value > 10)
                        {
                            throw new InvalidDataException("event_window confirmation timeout must be > 0 and <= 10 seconds");
                        }
                    }
                }
                if (valid && name.Length > 0)
                {
                    _reactionRules.Add(new ReactionRuleRow(
                        trigger,
                        name,
                        response,
                        distance,
                        actionType,
                        actionName,
                        activateEvent.Length == 0 ? null : activateEvent,
                        releaseEvent,
                        releaseName,
                        confirmationTimeoutSeconds
                    ));
                }
            }
        }
        RebindReactionRuleList();
    }

    private void RebindReactionRuleList(int selectedIndex = -1)
    {
        _reactionRuleList.Items.Clear();
        foreach (var rule in _reactionRules)
        {
            var distance = rule.Distance.HasValue ? $" | {rule.Distance.Value:0.0}y" : "";
            var action = rule.Response == "use_action" ? $" | {rule.ActionType}: {rule.ActionName}" : "";
            var lifecycle = rule.Trigger == "event_window"
                ? $" | {rule.ActivateEvent}:{rule.Name} -> {rule.ReleaseEvent}:{rule.ReleaseName}"
                    + (rule.ConfirmationTimeoutSeconds.HasValue ? $" | confirm {rule.ConfirmationTimeoutSeconds.Value:0.0}s" : "")
                : "";
            _reactionRuleList.Items.Add($"{rule.Trigger} | {rule.Name} | {rule.Response}{distance}{action}{lifecycle}");
        }
        if (_reactionRuleList.Items.Count > 0 && selectedIndex >= 0)
        {
            _reactionRuleList.SelectedIndex = Math.Min(selectedIndex, _reactionRuleList.Items.Count - 1);
        }
    }

    private void RefreshReactionResponseOptions()
    {
        _reactionResponseCombo.Items.Clear();
        var trigger = _reactionTriggerCombo.SelectedItem?.ToString();
        if (string.Equals(trigger, "enemy_buff", StringComparison.Ordinal))
        {
            _reactionResponseCombo.Items.Add("stop_attacking");
        }
        else if (string.Equals(trigger, "event_window", StringComparison.Ordinal))
        {
            _reactionResponseCombo.Items.AddRange(["stop_attacking", "turn_away"]);
        }
        else
        {
            _reactionResponseCombo.Items.AddRange(["turn_away", "run_away", "move_to_range", "use_action"]);
        }
        _reactionResponseCombo.SelectedIndex = 0;
        RefreshReactionDistanceState();
    }

    private void RefreshReactionDistanceState()
    {
        var trigger = _reactionTriggerCombo.SelectedItem?.ToString();
        var response = _reactionResponseCombo.SelectedItem?.ToString();
        _reactionDistance.Enabled = response is "run_away" or "move_to_range";
        var actionEnabled = response == "use_action";
        _reactionActionType.Enabled = actionEnabled;
        _reactionActionName.Enabled = actionEnabled;
        var lifecycleEnabled = string.Equals(trigger, "event_window", StringComparison.Ordinal);
        _reactionLifecycleEditor.Visible = lifecycleEnabled;
        _reactionConfirmationTimeout.Enabled = lifecycleEnabled
            && string.Equals(_reactionReleaseEvent.SelectedItem?.ToString(), "buff_lost", StringComparison.Ordinal);
        if (actionEnabled)
        {
            _reactionActionType.SelectedItem = "spell";
            RefreshReactionActionSpellOptions();
        }
    }

    private void OnReactionTriggerChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        RefreshReactionResponseOptions();
    }

    private void OnReactionConfigChanged()
    {
        if (_suppressEvents || string.IsNullOrWhiteSpace(_selectedSid))
        {
            return;
        }
        CaptureWorkingProfileFromUi(_selectedSid);
    }

    private string EncounterIdValue()
    {
        return _encounterId.SelectedItem?.ToString() switch
        {
            "Ghatjot — Sortie Area A" => "sortie_ghatjot",
            "Dhartok — Sortie Area E (validation pending)" => "sortie_dhartok",
            "Kei — Omen" => "kei",
            "Saved by the Bell — GEO Ergon quest" => "saved_by_the_bell",
            _ => throw new InvalidOperationException("unsupported encounter selection"),
        };
    }

    private static string EncounterPolicyValue(ComboBox combo)
    {
        return combo.SelectedItem?.ToString() switch
        {
            "Enforce" => "enforce",
            "Warn" => "warn",
            "Off" => "off",
            _ => throw new InvalidOperationException("unsupported encounter policy selection"),
        };
    }

    private static string EncounterPolicyDisplay(string mode, string field)
    {
        return mode switch
        {
            "enforce" => "Enforce",
            "warn" => "Warn",
            "off" => "Off",
            _ => throw new InvalidDataException($"unsupported {field} encounter policy: {mode}"),
        };
    }

    private void ApplyEncounterConfigFromSnapshot(JsonElement snapshot)
    {
        _encounterEnabled.Checked = SessionStateHelper.GetBool(snapshot, "encounter_enabled", false);
        var encounterId = SessionStateHelper.GetString(snapshot, "encounter_id", "sortie_ghatjot");
        _encounterId.SelectedItem = encounterId switch
        {
            "sortie_ghatjot" => "Ghatjot — Sortie Area A",
            "sortie_dhartok" => "Dhartok — Sortie Area E (validation pending)",
            "kei" => "Kei — Omen",
            "saved_by_the_bell" => "Saved by the Bell — GEO Ergon quest",
            _ => throw new InvalidDataException($"unsupported encounter ID in UI profile: {encounterId}"),
        };
        var repeatDefault = encounterId == "sortie_dhartok" ? "warn" : "off";
        _encounterWaterDamage.SelectedItem = EncounterPolicyDisplay(
            SessionStateHelper.GetString(snapshot, "encounter_water_damage", "enforce"),
            "direct Water"
        );
        _encounterWaterSkillchain.SelectedItem = EncounterPolicyDisplay(
            SessionStateHelper.GetString(snapshot, "encounter_water_skillchain", "enforce"),
            "Water skillchain"
        );
        _encounterRepeatActionWall.SelectedItem = EncounterPolicyDisplay(
            SessionStateHelper.GetString(snapshot, "encounter_repeat_action_wall", repeatDefault),
            "repeat-action"
        );
        var repeatGuardRaw = SessionStateHelper.GetString(snapshot, "encounter_repeat_action_guard_s", "10");
        if (!decimal.TryParse(repeatGuardRaw, NumberStyles.Float, CultureInfo.InvariantCulture, out var repeatGuard))
        {
            throw new InvalidDataException($"encounter repeat-action guard is not numeric: {repeatGuardRaw}");
        }
        if (repeatGuard < _encounterRepeatActionGuard.Minimum || repeatGuard > _encounterRepeatActionGuard.Maximum)
        {
            throw new InvalidDataException(
                $"encounter repeat-action guard is outside {_encounterRepeatActionGuard.Minimum}..{_encounterRepeatActionGuard.Maximum}: {repeatGuard}"
            );
        }
        _encounterRepeatActionGuard.Value = repeatGuard;
        var dealerName = SessionStateHelper.GetString(snapshot, "kei_elemental_dealer_name", "");
        BindPartyCombo(_keiElementalDealer, _partyOptions, dealerName);
        _keiWaterProbeSpell.Text = SessionStateHelper.GetString(snapshot, "kei_water_probe_spell", "Water");
        _keiWaterDamageSpell.Text = SessionStateHelper.GetString(snapshot, "kei_water_damage_spell", "Water III");
        _keiIceProbeSpell.Text = SessionStateHelper.GetString(snapshot, "kei_ice_probe_spell", "Blizzard");
        _keiIceDamageSpell.Text = SessionStateHelper.GetString(snapshot, "kei_ice_damage_spell", "Blizzard III");
        ApplyFormationNumber(snapshot, "kei_sustain_interval_s", _keiSustainInterval, "2.5");
        ApplyFormationNumber(snapshot, "kei_probe_timeout_s", _keiProbeTimeout, "3");
        ApplyFormationNumber(snapshot, "kei_fullers_target_distance", _keiFullersTargetDistance, "12");
        ApplyFormationNumber(snapshot, "kei_fullers_prearm_hpp_margin", _keiFullersPrearmMargin, "1");
        RefreshKeiSpellOptions();
        UpdateEncounterUiState();
    }

    private void OnEncounterSelectionChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        if (EncounterIdValue() != "kei")
        {
            _encounterRepeatActionWall.SelectedItem = EncounterIdValue() == "sortie_dhartok" ? "Warn" : "Off";
        }
        OnEncounterConfigChanged();
    }

    private void OnEncounterConfigChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        UpdateEncounterUiState();
        if (!string.IsNullOrWhiteSpace(_selectedSid))
        {
            CaptureWorkingProfileFromUi(_selectedSid);
        }
    }

    private bool ValidateEncounterConfiguration(out string error)
    {
        error = "";
        if (!_encounterEnabled.Checked)
        {
            return true;
        }
        var encounterId = EncounterIdValue();
        if (encounterId == "kei")
        {
            if (string.IsNullOrWhiteSpace(SelectedPartyName(_keiElementalDealer)))
            {
                error = "Kei requires an Elemental Damage Dealer.";
                return false;
            }
            var spells = new[]
            {
                _keiWaterProbeSpell.Text,
                _keiWaterDamageSpell.Text,
                _keiIceProbeSpell.Text,
                _keiIceDamageSpell.Text,
            };
            if (spells.Any(string.IsNullOrWhiteSpace))
            {
                error = "Kei requires all four elemental spell selections.";
                return false;
            }
            var selectedCharacter = _sessionMetaBySid.TryGetValue(_selectedSid ?? "", out var meta)
                ? meta.CharName
                : "";
            if (string.Equals(selectedCharacter, SelectedPartyName(_keiElementalDealer), StringComparison.OrdinalIgnoreCase)
                && _pathPullSpellOptions.Count > 0
                && spells.Any(spell => !_pathPullSpellOptions.Contains(spell.Trim(), StringComparer.OrdinalIgnoreCase)))
            {
                error = "One or more Kei spells are unavailable to the configured dealer's current job.";
                return false;
            }
            return true;
        }
        if (encounterId == "sortie_ghatjot" && EncounterPolicyValue(_encounterRepeatActionWall) != "off")
        {
            error = "Ghatjot does not use the repeated WS/BP policy; set it to Off.";
            return false;
        }
        return true;
    }

    private void UpdateEncounterUiState()
    {
        var enabled = _encounterEnabled.Checked;
        _encounterConfigPanel.Enabled = enabled;
        var isDhartok = EncounterIdValue() == "sortie_dhartok";
        var isKei = EncounterIdValue() == "kei";
        var isSavedByBell = EncounterIdValue() == "saved_by_the_bell";
        _keiConfigPanel.Visible = isKei;
        _encounterRepeatActionWall.Enabled = enabled && isDhartok;
        _encounterRepeatActionGuard.Enabled = enabled && isDhartok;
        _encounterWaterDamage.Enabled = enabled && !isKei && !isSavedByBell;
        _encounterWaterSkillchain.Enabled = enabled && !isKei && !isSavedByBell;
        _keiConfigPanel.Enabled = enabled && isKei;
        var valid = ValidateEncounterConfiguration(out var error);
        _encounterValidation.Text = !enabled
            ? "Encounter safeguards are disabled for this profile."
            : !valid
                ? error
                : isKei
                    ? "Kei elemental maintenance and Dancing Fullers reaction are ready to save."
                : isSavedByBell
                    ? "Saved by the Bell Luopan weakness automation is ready to save."
                : isDhartok
                    ? "Dhartok policy and validated cloud tracking are ready to save."
                    : "Ghatjot safeguards are ready to save."
            ;
        _encounterValidation.ForeColor = !enabled || valid ? SystemColors.ControlText : Color.Firebrick;
    }

    private string FormationEncounterValue()
    {
        return _formationEncounter.SelectedItem?.ToString() switch
        {
            "Lady Lilith — Easy" => "lilith_easy",
            "Ghatjot — Generic geometry" => "sortie_ghatjot",
            "Dhartok — Generic geometry (hazards pending validation)" => "sortie_dhartok",
            _ => throw new InvalidOperationException("unsupported formation encounter selection"),
        };
    }

    private void RefreshKeiSpellOptions()
    {
        foreach (var combo in new[] { _keiWaterProbeSpell, _keiWaterDamageSpell, _keiIceProbeSpell, _keiIceDamageSpell })
        {
            var selected = combo.Text;
            combo.Items.Clear();
            foreach (var spell in _pathPullSpellOptions)
            {
                combo.Items.Add(spell);
            }
            combo.Text = selected;
        }
    }

    private string FormationPlacementModeValue()
    {
        return _formationPlacementMode.SelectedItem?.ToString() switch
        {
            "Radial band" => "radial_band",
            "Polar band" => "polar_band",
            _ => throw new InvalidOperationException("unsupported formation placement mode"),
        };
    }

    private string FormationAnchorValue()
    {
        return _formationAnchor.SelectedItem?.ToString() switch
        {
            "Boss" => "boss",
            "Encounter origin" => "encounter_origin",
            "Party member" => "member",
            _ => throw new InvalidOperationException("unsupported formation anchor"),
        };
    }

    private string FormationAxisTypeValue()
    {
        return _formationAxisType.SelectedItem?.ToString() switch
        {
            "Boss to member" => "boss_to_member",
            "Boss heading" => "boss_heading",
            _ => throw new InvalidOperationException("unsupported formation axis"),
        };
    }

    private string FormationRoleValue()
    {
        return _formationRole.SelectedItem?.ToString() switch
        {
            "Disabled" => "disabled",
            "Tank" => "tank",
            "DPS" => "dps",
            "Healer" => "healer",
            _ => throw new InvalidOperationException("unsupported formation role selection"),
        };
    }

    private List<string> SelectedFormationRequiredPartyNames()
    {
        return _formationRequiredParty.CheckedItems
            .Cast<object>()
            .Select(item => NormalizePartyName(item?.ToString() ?? ""))
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private JsonObject CaptureNamedFormationGeometry()
    {
        var geometry = new JsonObject
        {
            ["formation_placement_mode"] = FormationPlacementModeValue(),
            ["formation_anchor"] = FormationAnchorValue(),
            ["formation_anchor_member"] = SelectedPartyName(_formationAnchorMember),
            ["formation_axis_type"] = FormationAxisTypeValue(),
            ["formation_axis_member"] = SelectedPartyName(_formationAxisMember),
            ["formation_preferred_radius"] = (double)_formationPreferredRadius.Value,
            ["formation_minimum_radius"] = (double)_formationMinimumRadius.Value,
            ["formation_maximum_radius"] = (double)_formationMaximumRadius.Value,
            ["formation_preferred_angle_deg"] = (double)_formationPreferredAngle.Value,
            ["formation_allowed_angle_half_width_deg"] = (double)_formationAllowedAngleHalfWidth.Value,
            ["formation_radius_step"] = (double)_formationRadiusStep.Value,
            ["formation_angle_step_deg"] = (double)_formationAngleStep.Value,
            ["formation_hysteresis_start_distance"] = (double)_formationHysteresisStart.Value,
            ["formation_hysteresis_stop_distance"] = (double)_formationHysteresisStop.Value,
            ["formation_avoid_encounter_hazards"] = _formationAvoidEncounterHazards.Checked,
            ["formation_hazard_margin"] = (double)_formationHazardMargin.Value,
            ["formation_safe_origin_radius"] = (double)_formationSafeOriginRadius.Value,
            ["formation_minimum_boss_distance"] = (double)_formationMinimumBossDistance.Value,
            ["formation_maximum_boss_distance"] = (double)_formationMaximumBossDistance.Value,
            ["formation_maximum_party_range"] = (double)_formationMaximumPartyRange.Value,
            ["formation_required_party_names"] = string.Join("|", SelectedFormationRequiredPartyNames()),
        };
        return geometry;
    }

    private void ApplyNamedFormationGeometry(JsonObject geometry)
    {
        using var document = JsonDocument.Parse(geometry.ToJsonString());
        var root = document.RootElement;
        _formationPlacementMode.SelectedItem = SessionStateHelper.GetString(root, "formation_placement_mode", "radial_band") == "polar_band"
            ? "Polar band" : "Radial band";
        _formationAnchor.SelectedItem = SessionStateHelper.GetString(root, "formation_anchor", "boss") switch
        {
            "boss" => "Boss",
            "encounter_origin" => "Encounter origin",
            "member" => "Party member",
            var value => throw new InvalidDataException($"unsupported named formation anchor: {value}"),
        };
        _formationAxisType.SelectedItem = SessionStateHelper.GetString(root, "formation_axis_type", "boss_to_member") == "boss_heading"
            ? "Boss heading" : "Boss to member";
        _formationAnchorMember.Text = SessionStateHelper.GetString(root, "formation_anchor_member", "");
        _formationAxisMember.Text = SessionStateHelper.GetString(root, "formation_axis_member", "");
        var requiredNames = SessionStateHelper.SplitOptions(
            root.TryGetProperty("formation_required_party_names", out var requiredNode) ? requiredNode : default
        );
        for (var i = 0; i < _formationRequiredParty.Items.Count; i++)
        {
            var partyName = NormalizePartyName(_formationRequiredParty.Items[i]?.ToString() ?? "");
            _formationRequiredParty.SetItemChecked(
                i,
                requiredNames.Any(name => string.Equals(NormalizePartyName(name), partyName, StringComparison.OrdinalIgnoreCase))
            );
        }
        ApplyFormationNumber(root, "formation_preferred_radius", _formationPreferredRadius, "3");
        ApplyFormationNumber(root, "formation_minimum_radius", _formationMinimumRadius, "2");
        ApplyFormationNumber(root, "formation_maximum_radius", _formationMaximumRadius, "4");
        ApplyFormationNumber(root, "formation_preferred_angle_deg", _formationPreferredAngle, "180");
        ApplyFormationNumber(root, "formation_allowed_angle_half_width_deg", _formationAllowedAngleHalfWidth, "60");
        ApplyFormationNumber(root, "formation_radius_step", _formationRadiusStep, "0.5");
        ApplyFormationNumber(root, "formation_angle_step_deg", _formationAngleStep, "10");
        ApplyFormationNumber(root, "formation_hysteresis_start_distance", _formationHysteresisStart, "1");
        ApplyFormationNumber(root, "formation_hysteresis_stop_distance", _formationHysteresisStop, "0.5");
        _formationAvoidEncounterHazards.Checked = SessionStateHelper.GetBool(root, "formation_avoid_encounter_hazards", false);
        ApplyFormationNumber(root, "formation_hazard_margin", _formationHazardMargin, "0");
        ApplyFormationNumber(root, "formation_safe_origin_radius", _formationSafeOriginRadius, "0");
        ApplyFormationNumber(root, "formation_minimum_boss_distance", _formationMinimumBossDistance, "0");
        ApplyFormationNumber(root, "formation_maximum_boss_distance", _formationMaximumBossDistance, "0");
        ApplyFormationNumber(root, "formation_maximum_party_range", _formationMaximumPartyRange, "0");
    }

    private void RebindNamedFormationList(int selectedIndex = -1)
    {
        _namedFormationList.Items.Clear();
        foreach (var entry in _namedFormations)
        {
            _namedFormationList.Items.Add(entry.MobName);
        }
        if (selectedIndex >= 0 && selectedIndex < _namedFormationList.Items.Count)
        {
            _namedFormationList.SelectedIndex = selectedIndex;
        }
    }

    private void OnNamedFormationAddUpdate()
    {
        var mobName = _namedFormationMobName.Text.Trim();
        if (mobName.Length == 0)
        {
            _formationValidation.Text = "Enter the exact named mob or boss name.";
            _formationValidation.ForeColor = Color.Firebrick;
            return;
        }
        if (!ValidateGenericFormationGeometry(out var error))
        {
            _formationValidation.Text = error;
            _formationValidation.ForeColor = Color.Firebrick;
            return;
        }
        var index = _namedFormations.FindIndex(x => string.Equals(x.MobName, mobName, StringComparison.OrdinalIgnoreCase));
        var row = new NamedFormationRow(mobName, CaptureNamedFormationGeometry());
        if (index >= 0)
        {
            _namedFormations[index] = row;
        }
        else
        {
            _namedFormations.Add(row);
            index = _namedFormations.Count - 1;
        }
        _namedFormationsEnabled.Checked = true;
        RebindNamedFormationList(index);
        OnFormationConfigChanged();
    }

    private void OnNamedFormationRemove()
    {
        var index = _namedFormationList.SelectedIndex;
        if (index < 0 || index >= _namedFormations.Count)
        {
            return;
        }
        _namedFormations.RemoveAt(index);
        if (_namedFormations.Count == 0)
        {
            _namedFormationsEnabled.Checked = false;
        }
        RebindNamedFormationList(Math.Min(index, _namedFormations.Count - 1));
        OnFormationConfigChanged();
    }

    private void OnNamedFormationSelectionChanged()
    {
        var index = _namedFormationList.SelectedIndex;
        if (index < 0 || index >= _namedFormations.Count)
        {
            return;
        }
        _namedFormationMobName.Text = _namedFormations[index].MobName;
        UpdateFormationUiState();
    }

    private void OnNamedFormationEditEncounter()
    {
        var index = _namedFormationList.SelectedIndex;
        if (index < 0 || index >= _namedFormations.Count)
        {
            return;
        }
        _suppressEvents = true;
        try
        {
            ApplyNamedFormationGeometry(_namedFormations[index].Geometry);
        }
        finally
        {
            _suppressEvents = false;
        }
        UpdateFormationUiState();
    }

    private bool ValidateGenericFormationGeometry(out string error)
    {
        error = "";
        if (_formationMaximumRadius.Value < _formationMinimumRadius.Value)
        {
            error = "Maximum radius must be at least minimum radius.";
            return false;
        }
        if (_formationPreferredRadius.Value < _formationMinimumRadius.Value
            || _formationPreferredRadius.Value > _formationMaximumRadius.Value)
        {
            error = "Preferred radius must be inside the minimum/maximum band.";
            return false;
        }
        if (FormationAnchorValue() == "member" && string.IsNullOrWhiteSpace(SelectedPartyName(_formationAnchorMember)))
        {
            error = "Choose an anchor party member.";
            return false;
        }
        if (FormationPlacementModeValue() == "polar_band"
            && FormationAxisTypeValue() == "boss_to_member"
            && string.IsNullOrWhiteSpace(SelectedPartyName(_formationAxisMember)))
        {
            error = "Choose a party member for the polar axis.";
            return false;
        }
        if (_formationHysteresisStart.Value < _formationHysteresisStop.Value)
        {
            error = "Formation start distance must be at least stop distance.";
            return false;
        }
        if (_formationMaximumBossDistance.Value > 0
            && _formationMaximumBossDistance.Value < _formationMinimumBossDistance.Value)
        {
            error = "Maximum boss distance must be at least minimum boss distance.";
            return false;
        }
        if (_formationMaximumPartyRange.Value > 0 && SelectedFormationRequiredPartyNames().Count == 0)
        {
            error = "Maximum party range requires at least one checked party member.";
            return false;
        }
        return true;
    }

    private void ApplyFormationConfigFromSnapshot(JsonElement snapshot, IReadOnlyList<string> partyOptions)
    {
        _formationEnabled.Checked = SessionStateHelper.GetBool(snapshot, "formation_enabled", false);
        _namedFormationsEnabled.Checked = SessionStateHelper.GetBool(snapshot, "named_formations_enabled", false);
        _namedFormations.Clear();
        if (snapshot.TryGetProperty("named_formation_entries", out var namedEntries)
            && namedEntries.ValueKind == JsonValueKind.Array)
        {
            foreach (var entry in namedEntries.EnumerateArray())
            {
                if (entry.ValueKind != JsonValueKind.Object)
                {
                    throw new InvalidDataException("named formation entries must be objects");
                }
                var mobName = SessionStateHelper.GetString(entry, "mob_name", "").Trim();
                if (mobName.Length == 0)
                {
                    throw new InvalidDataException("named formation entry is missing mob_name");
                }
                var geometry = JsonNode.Parse(entry.GetRawText())?.AsObject()
                    ?? throw new InvalidDataException("named formation entry could not be parsed");
                geometry.Remove("mob_name");
                _namedFormations.Add(new NamedFormationRow(mobName, geometry));
            }
        }
        RebindNamedFormationList();
        _namedFormationMobName.Text = "";
        var encounter = SessionStateHelper.GetString(snapshot, "formation_encounter", "lilith_easy");
        _formationEncounter.SelectedItem = encounter switch
        {
            "lilith_easy" => "Lady Lilith — Easy",
            "sortie_ghatjot" => "Ghatjot — Generic geometry",
            "sortie_dhartok" => "Dhartok — Generic geometry (hazards pending validation)",
            _ => throw new InvalidDataException($"unsupported formation encounter in UI profile: {encounter}"),
        };
        _formationMockEnabled.Checked = SessionStateHelper.GetBool(snapshot, "formation_mock_enabled", false);
        _formationMockMobName.Text = SessionStateHelper.GetString(snapshot, "formation_mock_mob_name", "").Trim();

        var role = SessionStateHelper.GetString(snapshot, "formation_role", "disabled");
        _formationRole.SelectedItem = role switch
        {
            "disabled" => "Disabled",
            "tank" => "Tank",
            "dps" => "DPS",
            "healer" => "Healer",
            _ => throw new InvalidDataException($"unsupported formation role in UI profile: {role}"),
        };

        var tankName = NormalizePartyName(SessionStateHelper.GetString(snapshot, "formation_tank_name"));
        var anchorMember = NormalizePartyName(SessionStateHelper.GetString(snapshot, "formation_anchor_member"));
        var axisMember = NormalizePartyName(SessionStateHelper.GetString(snapshot, "formation_axis_member"));
        var required = SessionStateHelper.SplitOptions(
            snapshot.TryGetProperty("formation_required_party_names", out var requiredNode) ? requiredNode : default
        );
        BindFormationPartyControls(partyOptions, tankName, anchorMember, axisMember, required);

        ApplyFormationNumber(snapshot, "formation_capture_stable_s", _formationCaptureStable, "0.5");
        ApplyFormationNumber(snapshot, "formation_capture_tolerance", _formationCaptureTolerance, "0.1");
        ApplyFormationNumber(snapshot, "formation_safe_radius", _formationSafeRadius, "16");
        ApplyFormationNumber(snapshot, "formation_tank_accept_radius", _formationTankAcceptRadius, "1.5");
        ApplyFormationNumber(snapshot, "formation_tank_return_radius", _formationTankReturnRadius, "3");
        ApplyFormationNumber(snapshot, "formation_dps_flank_angle_deg", _formationDpsFlankAngle, "90");
        ApplyFormationNumber(snapshot, "formation_dps_melee_radius", _formationDpsMeleeRadius, "3");
        ApplyFormationNumber(snapshot, "formation_dps_position_tolerance", _formationDpsPositionTolerance, "1.5");
        ApplyFormationNumber(snapshot, "formation_healer_preferred_radius", _formationHealerPreferredRadius, "12");
        ApplyFormationNumber(snapshot, "formation_healer_minimum_boss_distance", _formationHealerMinimumBossDistance, "8");
        ApplyFormationNumber(snapshot, "formation_healer_maximum_party_range", _formationHealerMaximumPartyRange, "18");
        ApplyFormationNumber(snapshot, "formation_healer_cone_half_angle_deg", _formationHealerConeHalfAngle, "50");
        ApplyFormationNumber(snapshot, "formation_healer_cone_safety_margin_deg", _formationHealerConeSafetyMargin, "15");
        ApplyFormationNumber(snapshot, "formation_healer_sample_step_deg", _formationHealerSampleStep, "10");
        _formationPlacementMode.SelectedItem = SessionStateHelper.GetString(snapshot, "formation_placement_mode", "radial_band") switch
        {
            "radial_band" => "Radial band",
            "polar_band" => "Polar band",
            var value => throw new InvalidDataException($"unsupported formation placement mode in UI profile: {value}"),
        };
        _formationAnchor.SelectedItem = SessionStateHelper.GetString(snapshot, "formation_anchor", "boss") switch
        {
            "boss" => "Boss",
            "encounter_origin" => "Encounter origin",
            "member" => "Party member",
            var value => throw new InvalidDataException($"unsupported formation anchor in UI profile: {value}"),
        };
        _formationAxisType.SelectedItem = SessionStateHelper.GetString(snapshot, "formation_axis_type", "boss_to_member") switch
        {
            "boss_to_member" => "Boss to member",
            "boss_heading" => "Boss heading",
            var value => throw new InvalidDataException($"unsupported formation axis in UI profile: {value}"),
        };
        ApplyFormationNumber(snapshot, "formation_preferred_radius", _formationPreferredRadius, "3");
        ApplyFormationNumber(snapshot, "formation_minimum_radius", _formationMinimumRadius, "2");
        ApplyFormationNumber(snapshot, "formation_maximum_radius", _formationMaximumRadius, "4");
        ApplyFormationNumber(snapshot, "formation_preferred_angle_deg", _formationPreferredAngle, "180");
        ApplyFormationNumber(snapshot, "formation_allowed_angle_half_width_deg", _formationAllowedAngleHalfWidth, "60");
        ApplyFormationNumber(snapshot, "formation_radius_step", _formationRadiusStep, "0.5");
        ApplyFormationNumber(snapshot, "formation_angle_step_deg", _formationAngleStep, "10");
        ApplyFormationNumber(snapshot, "formation_hysteresis_start_distance", _formationHysteresisStart, "1");
        ApplyFormationNumber(snapshot, "formation_hysteresis_stop_distance", _formationHysteresisStop, "0.5");
        _formationAvoidEncounterHazards.Checked = SessionStateHelper.GetBool(
            snapshot,
            "formation_avoid_encounter_hazards",
            false
        );
        ApplyFormationNumber(snapshot, "formation_hazard_margin", _formationHazardMargin, "0");
        ApplyFormationNumber(snapshot, "formation_safe_origin_radius", _formationSafeOriginRadius, "0");
        ApplyFormationNumber(snapshot, "formation_minimum_boss_distance", _formationMinimumBossDistance, "0");
        ApplyFormationNumber(snapshot, "formation_maximum_boss_distance", _formationMaximumBossDistance, "0");
        ApplyFormationNumber(snapshot, "formation_maximum_party_range", _formationMaximumPartyRange, "0");
    }

    private void BindFormationPartyControls(
        IReadOnlyList<string> partyOptions,
        string tankName,
        string anchorMember,
        string axisMember,
        IReadOnlyList<string> required
    )
    {
        var names = partyOptions
            .Concat(required)
            .Append(tankName)
            .Append(anchorMember)
            .Append(axisMember)
            .Select(NormalizePartyName)
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(name => name, StringComparer.OrdinalIgnoreCase)
            .ToList();
        BindPartyCombo(_formationTankName, names, tankName);
        BindPartyCombo(_formationAnchorMember, names, anchorMember);
        BindPartyCombo(_formationAxisMember, names, axisMember);
        _formationRequiredParty.Items.Clear();
        foreach (var name in names)
        {
            var check = required.Any(selected => string.Equals(NormalizePartyName(selected), name, StringComparison.OrdinalIgnoreCase));
            _formationRequiredParty.Items.Add(name, check);
        }
    }

    private static void ApplyFormationNumber(JsonElement snapshot, string key, NumericUpDown control, string defaultValue)
    {
        var raw = SessionStateHelper.GetString(snapshot, key, defaultValue);
        if (!decimal.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
        {
            throw new InvalidDataException($"formation setting {key} is not numeric: {raw}");
        }
        if (value < control.Minimum || value > control.Maximum)
        {
            throw new InvalidDataException($"formation setting {key} is outside {control.Minimum}..{control.Maximum}: {value}");
        }
        control.Value = value;
    }

    private void OnFormationRequiredPartyItemCheck()
    {
        if (_suppressEvents || !IsHandleCreated)
        {
            return;
        }
        BeginInvoke(
            () =>
            {
                if (!IsDisposed)
                {
                    OnFormationConfigChanged();
                }
            }
        );
    }

    private void OnFormationConfigChanged()
    {
        if (_suppressEvents)
        {
            return;
        }
        UpdateFormationUiState();
        if (!string.IsNullOrWhiteSpace(_selectedSid))
        {
            CaptureWorkingProfileFromUi(_selectedSid);
        }
    }

    private void OnFormationEnableOwnership()
    {
        if (!_boolChecks.TryGetValue("domain_movement_enabled", out var movementDomain))
        {
            throw new InvalidOperationException("movement domain control is unavailable");
        }
        var wasSuppressed = _suppressEvents;
        _suppressEvents = true;
        try
        {
            movementDomain.Checked = true;
        }
        finally
        {
            _suppressEvents = wasSuppressed;
        }
        UpdateFormationUiState();
        if (!string.IsNullOrWhiteSpace(_selectedSid))
        {
            CaptureWorkingProfileFromUi(_selectedSid);
        }
    }

    private bool ValidateFormationConfiguration(out string error)
    {
        error = "";
        if (!_formationEnabled.Checked && !_namedFormationsEnabled.Checked)
        {
            return true;
        }
        if (!_boolChecks.TryGetValue("domain_movement_enabled", out var movementDomain) || !movementDomain.Checked)
        {
            error = "Movement domain must be enabled.";
            return false;
        }
        if (_namedFormationsEnabled.Checked && _namedFormations.Count == 0)
        {
            error = "Add at least one exact named mob or boss formation.";
            return false;
        }
        if (!_formationEnabled.Checked)
        {
            return true;
        }
        var encounter = FormationEncounterValue();
        if (_formationMockEnabled.Checked && encounter == "lilith_easy")
        {
            error = "Formation mock testing is available only for generic formations.";
            return false;
        }
        if (_formationMockEnabled.Checked && string.IsNullOrWhiteSpace(_formationMockMobName.Text))
        {
            error = "Enter the exact normal-mob name for formation mock testing.";
            return false;
        }
        if (encounter == "lilith_easy")
        {
            if (FormationRoleValue() == "disabled")
            {
                error = "Choose Tank, DPS, or Healer for this character.";
                return false;
            }
            if (string.IsNullOrWhiteSpace(SelectedPartyName(_formationTankName)))
            {
                error = "Select or enter the tank character.";
                return false;
            }
            if (_formationTankReturnRadius.Value <= _formationTankAcceptRadius.Value)
            {
                error = "Tank return radius must be greater than the centered radius.";
                return false;
            }
            if (_formationHealerPreferredRadius.Value >= _formationSafeRadius.Value)
            {
                error = "Healer preferred radius must be inside the arena safe radius.";
                return false;
            }
            return true;
        }
        if (!_encounterEnabled.Checked || EncounterIdValue() != encounter)
        {
            error = "Generic formation requires enabled encounter policy with the same Sortie encounter.";
            return false;
        }
        return ValidateGenericFormationGeometry(out error);
    }

    private void UpdateFormationUiState()
    {
        var enabled = _formationEnabled.Checked;
        var namedEnabled = _namedFormationsEnabled.Checked;
        var anyEnabled = enabled || namedEnabled;
        _formationConfigPanel.Enabled = anyEnabled;
        var generic = FormationEncounterValue() != "lilith_easy";
        _namedFormationMobName.Enabled = namedEnabled;
        _namedFormationAddUpdate.Enabled = namedEnabled;
        _namedFormationList.Enabled = namedEnabled;
        _namedFormationRemove.Enabled = namedEnabled && _namedFormationList.SelectedIndex >= 0;
        _namedFormationEditEncounter.Enabled = namedEnabled && _namedFormationList.SelectedIndex >= 0;
        _formationEncounter.Enabled = enabled;
        _formationMockEnabled.Enabled = enabled && generic;
        _formationMockMobName.Enabled = enabled && generic && _formationMockEnabled.Checked;
        _formationRole.Enabled = enabled && !generic;
        _formationTankName.Enabled = enabled && !generic;
        _formationCaptureStable.Enabled = enabled && !generic;
        _formationCaptureTolerance.Enabled = enabled && !generic;
        _formationSafeRadius.Enabled = enabled && !generic;
        _formationTankAcceptRadius.Enabled = enabled && !generic;
        _formationTankReturnRadius.Enabled = enabled && !generic;
        _formationDpsFlankAngle.Enabled = enabled && !generic;
        _formationDpsMeleeRadius.Enabled = enabled && !generic;
        _formationDpsPositionTolerance.Enabled = enabled && !generic;
        _formationHealerPreferredRadius.Enabled = enabled && !generic;
        _formationHealerMinimumBossDistance.Enabled = enabled && !generic;
        _formationHealerMaximumPartyRange.Enabled = enabled && !generic;
        _formationHealerConeHalfAngle.Enabled = enabled && !generic;
        _formationHealerConeSafetyMargin.Enabled = enabled && !generic;
        _formationHealerSampleStep.Enabled = enabled && !generic;
        var geometryEnabled = namedEnabled || (enabled && generic);
        _formationPlacementMode.Enabled = geometryEnabled;
        _formationAnchor.Enabled = geometryEnabled;
        _formationAnchorMember.Enabled = geometryEnabled && FormationAnchorValue() == "member";
        _formationAxisType.Enabled = geometryEnabled && FormationPlacementModeValue() == "polar_band";
        _formationAxisMember.Enabled = geometryEnabled
            && FormationPlacementModeValue() == "polar_band"
            && FormationAxisTypeValue() == "boss_to_member";
        _formationPreferredRadius.Enabled = geometryEnabled;
        _formationMinimumRadius.Enabled = geometryEnabled;
        _formationMaximumRadius.Enabled = geometryEnabled;
        _formationPreferredAngle.Enabled = geometryEnabled && FormationPlacementModeValue() == "polar_band";
        _formationAllowedAngleHalfWidth.Enabled = geometryEnabled && FormationPlacementModeValue() == "polar_band";
        _formationRadiusStep.Enabled = geometryEnabled;
        _formationAngleStep.Enabled = geometryEnabled;
        _formationHysteresisStart.Enabled = geometryEnabled;
        _formationHysteresisStop.Enabled = geometryEnabled;
        _formationAvoidEncounterHazards.Enabled = geometryEnabled;
        _formationHazardMargin.Enabled = geometryEnabled;
        _formationSafeOriginRadius.Enabled = geometryEnabled;
        _formationMinimumBossDistance.Enabled = geometryEnabled;
        _formationMaximumBossDistance.Enabled = geometryEnabled;
        _formationMaximumPartyRange.Enabled = geometryEnabled;
        _formationRequiredParty.Enabled = geometryEnabled && _formationMaximumPartyRange.Value > 0;
        var valid = ValidateFormationConfiguration(out var error);
        _formationValidation.Text = !anyEnabled
            ? "Encounter and named formations are disabled for this profile."
            : valid
                ? _formationMockEnabled.Checked
                    ? "Ready to save. Mock mode drives formation only; encounter policies and hazards remain on live encounter state."
                    : generic && FormationEncounterValue() == "sortie_dhartok"
                    ? "Ready to save. Validated Dhartok clouds are avoided when encounter hazard avoidance is enabled."
                    : "Ready to save. Movement domain is enabled."
                : error;
        _formationValidation.ForeColor = !anyEnabled || valid ? SystemColors.ControlText : Color.Firebrick;
        var movementEnabled = _boolChecks.TryGetValue("domain_movement_enabled", out var movementDomain)
            && movementDomain.Checked;
        _formationEnableOwnership.Visible = anyEnabled && !movementEnabled;
    }

    private void OnReactionRuleAdd()
    {
        if (_suppressEvents)
        {
            return;
        }
        var trigger = _reactionTriggerCombo.SelectedItem?.ToString() ?? "";
        var name = (_reactionName.Text ?? "").Trim();
        var response = _reactionResponseCombo.SelectedItem?.ToString() ?? "";
        var activateEvent = trigger == "event_window" ? _reactionActivateEvent.SelectedItem?.ToString() ?? "" : "";
        var valid = (trigger == "ability_window" && (response == "turn_away" || response == "run_away" || response == "move_to_range" || response == "use_action"))
            || (trigger == "enemy_buff" && response == "stop_attacking")
            || (trigger == "event_window" && (response is "stop_attacking" or "turn_away")
                && activateEvent is "spell_start" or "ability_start" or "buff_gained");
        if (!valid || name.Length == 0)
        {
            return;
        }
        if (_reactionRules.Any(x => string.Equals(x.Trigger, trigger, StringComparison.Ordinal)
            && string.Equals(x.Name, name, StringComparison.OrdinalIgnoreCase)
            && (trigger != "event_window"
                || (string.Equals(x.ActivateEvent, activateEvent, StringComparison.Ordinal)
                    && string.Equals(x.Response, response, StringComparison.Ordinal)))))
        {
            return;
        }
        var distance = response is "run_away" or "move_to_range" ? decimal.ToDouble(_reactionDistance.Value) : (double?)null;
        string? actionType = null;
        string? actionName = null;
        if (response == "use_action")
        {
            actionType = _reactionActionType.SelectedItem?.ToString() ?? "";
            actionName = (_reactionActionName.Text ?? "").Trim();
            if (actionType != "spell" || actionName.Length == 0)
            {
                return;
            }
        }
        string? releaseEvent = null;
        string? releaseName = null;
        double? confirmationTimeoutSeconds = null;
        if (trigger == "event_window")
        {
            releaseEvent = _reactionReleaseEvent.SelectedItem?.ToString() ?? "";
            releaseName = (_reactionReleaseName.Text ?? "").Trim();
            if (releaseName.Length == 0)
            {
                releaseName = name;
            }
            if (releaseEvent is not ("spell_end" or "ability_end" or "buff_lost"))
            {
                return;
            }
            if (releaseEvent == "buff_lost")
            {
                confirmationTimeoutSeconds = decimal.ToDouble(_reactionConfirmationTimeout.Value);
            }
        }
        _reactionRules.Add(new ReactionRuleRow(
            trigger,
            name,
            response,
            distance,
            actionType,
            actionName,
            activateEvent.Length == 0 ? null : activateEvent,
            releaseEvent,
            releaseName,
            confirmationTimeoutSeconds
        ));
        _reactionName.Text = "";
        if (trigger == "event_window")
        {
            _reactionReleaseName.Text = "";
        }
        if (response == "use_action")
        {
            _reactionActionName.Text = "";
        }
        RebindReactionRuleList(_reactionRules.Count - 1);
        OnReactionConfigChanged();
    }

    private void OnReactionRuleRemove()
    {
        var index = _reactionRuleList.SelectedIndex;
        if (_suppressEvents || index < 0 || index >= _reactionRules.Count)
        {
            return;
        }
        _reactionRules.RemoveAt(index);
        RebindReactionRuleList(Math.Min(index, _reactionRules.Count - 1));
        OnReactionConfigChanged();
    }

    private void OnReactionRuleMove(int direction)
    {
        var index = _reactionRuleList.SelectedIndex;
        var next = index + direction;
        if (_suppressEvents || index < 0 || next < 0 || next >= _reactionRules.Count)
        {
            return;
        }
        (_reactionRules[index], _reactionRules[next]) = (_reactionRules[next], _reactionRules[index]);
        RebindReactionRuleList(next);
        OnReactionConfigChanged();
    }

    private void OnBrdListAdd(bool dummy)
    {
        if (_suppressEvents)
        {
            return;
        }
        var combo = dummy ? _brdDummyCombo : _brdSongCombo;
        var list = dummy ? _brdDummyList : _brdSongList;
        var other = dummy ? _brdSongList : _brdDummyList;
        var name = combo.SelectedItem?.ToString() ?? "";
        if (string.IsNullOrWhiteSpace(name)
            || list.Items.Cast<object>().Any(x => string.Equals(x?.ToString(), name, StringComparison.Ordinal))
            || other.Items.Cast<object>().Any(x => string.Equals(x?.ToString(), name, StringComparison.Ordinal)))
        {
            return;
        }
        if (!dummy && !string.IsNullOrWhiteSpace(_selectedSid) && _sessionMetaBySid.TryGetValue(_selectedSid, out var meta))
        {
            var subOnly = !string.Equals(meta.Job, "BRD", StringComparison.OrdinalIgnoreCase)
                && string.Equals(meta.SubJob, "BRD", StringComparison.OrdinalIgnoreCase);
            if (subOnly && list.Items.Count >= 1)
            {
                return;
            }
        }
        list.Items.Add(name);
        list.SelectedIndex = list.Items.Count - 1;
        RefreshBrdMarcatoOptions();
        OnBrdConfigChanged();
    }

    private void OnBrdListRemove(bool dummy)
    {
        if (_suppressEvents)
        {
            return;
        }
        var list = dummy ? _brdDummyList : _brdSongList;
        var index = list.SelectedIndex;
        if (index < 0)
        {
            return;
        }
        list.Items.RemoveAt(index);
        if (list.Items.Count > 0)
        {
            list.SelectedIndex = Math.Min(index, list.Items.Count - 1);
        }
        RefreshBrdMarcatoOptions();
        OnBrdConfigChanged();
    }

    private void OnBrdListMove(bool dummy, int direction)
    {
        if (_suppressEvents)
        {
            return;
        }
        var list = dummy ? _brdDummyList : _brdSongList;
        var from = list.SelectedIndex;
        var to = from + direction;
        if (from < 0 || to < 0 || to >= list.Items.Count)
        {
            return;
        }
        var item = list.Items[from];
        list.Items.RemoveAt(from);
        list.Items.Insert(to, item);
        list.SelectedIndex = to;
        RefreshBrdMarcatoOptions();
        OnBrdConfigChanged();
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

    private void OnCorCrookedChanged(int slot, bool enabled)
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
        if (_sessionMetaBySid.TryGetValue(sid, out var meta))
        {
            var main = (meta.Job ?? "").ToUpperInvariant();
            var sub = (meta.SubJob ?? "").ToUpperInvariant();
            var subCorOnly = !string.Equals(main, "COR", StringComparison.Ordinal) && string.Equals(sub, "COR", StringComparison.Ordinal);
            if (subCorOnly)
            {
                _suppressEvents = true;
                try
                {
                    _corCrookedRoll1.Checked = false;
                    _corCrookedRoll2.Checked = false;
                }
                finally
                {
                    _suppressEvents = false;
                }
                Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "cor_crooked_roll_slot", ["value"] = "0" });
                return;
            }
        }
        _suppressEvents = true;
        try
        {
            if (slot == 1 && enabled)
            {
                _corCrookedRoll2.Checked = false;
            }
            else if (slot == 2 && enabled)
            {
                _corCrookedRoll1.Checked = false;
            }
        }
        finally
        {
            _suppressEvents = false;
        }
        var slotVal = _corCrookedRoll1.Checked ? 1 : (_corCrookedRoll2.Checked ? 2 : 0);
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "cor_crooked_roll_slot", ["value"] = slotVal.ToString(CultureInfo.InvariantCulture) });
    }

    private void OnCorFlagChanged(string key, bool value)
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
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = key, ["value"] = value ? "on" : "off" });
    }

    private void RenderCorRangePartyChecks(string sid, IReadOnlyList<string> selectedNames)
    {
        var selectedSet = new HashSet<string>(selectedNames.Where(x => !string.IsNullOrWhiteSpace(x)), StringComparer.OrdinalIgnoreCase);
        var me = _sessionMetaBySid.TryGetValue(sid, out var meta) ? (meta.CharName ?? "") : "";
        var options = _corPartyOptions.Count > 0 ? _corPartyOptions : CurrentPartyNameOptions();
        var ucNames = GetUcNameSet();
        _corRangePartyPanel.SuspendLayout();
        try
        {
            _corRangePartyPanel.Controls.Clear();
            foreach (var name in options.Where(n => !string.IsNullOrWhiteSpace(n) && !string.Equals(n, me, StringComparison.OrdinalIgnoreCase)))
            {
                var cb = new CheckBox
                {
                    AutoSize = true,
                    Text = $"{name} [{(ucNames.Contains(name) ? "UC" : "party")}]",
                    Checked = selectedSet.Contains(name),
                    Tag = name,
                };
                cb.CheckedChanged += (_, _) => OnCorRangePartySelectionChanged();
                _corRangePartyPanel.Controls.Add(cb);
            }
        }
        finally
        {
            _corRangePartyPanel.ResumeLayout();
        }
    }

    private void OnCorRangePartySelectionChanged()
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
        var names = _corRangePartyPanel.Controls.OfType<CheckBox>()
            .Where(c => c.Checked)
            .Select(c => c.Tag?.ToString() ?? c.Text)
            .Where(n => !string.IsNullOrWhiteSpace(n))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "cor_roll_range_replace_names",
                ["value"] = string.Join("|", names),
            }
        );
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
            // Hunter edits are profile-local until explicit Save. Capture immediately
            // so a subsequent mirror refresh cannot rebuild the list from stale state.
            CaptureWorkingProfileFromUi(sid);
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
            // Keep the per-session working profile authoritative for unsaved list edits.
            CaptureWorkingProfileFromUi(sid);
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

	private void OnCampSet()
	{
		var sid = RequireSelectedSid();
		if (sid is null)
		{
			return;
		}
		if (!SelectedSessionSupportsCampRuntime())
		{
			_campStatus.Text = "Camp unavailable — reload UnifiedCombat addon";
			return;
		}
		Forward(sid, new Dictionary<string, object?> { ["op"] = "camp_set" });
		_campStatus.Text = "Setting camp…";
	}

	private void OnCampClear()
	{
		var sid = RequireSelectedSid();
		if (sid is null)
		{
			return;
		}
		if (!SelectedSessionSupportsCampRuntime())
		{
			_campStatus.Text = "Camp unavailable — reload UnifiedCombat addon";
			return;
		}
		Forward(sid, new Dictionary<string, object?> { ["op"] = "camp_clear" });
		_campStatus.Text = "Clearing camp…";
	}

	private bool TryGetSelectedRuntimeState(out JsonElement state)
	{
		state = default;
		if (string.IsNullOrWhiteSpace(_selectedSid) || _snapshotDoc is null)
		{
			return false;
		}
		var root = _snapshotDoc.RootElement;
		return root.TryGetProperty("sessions", out var sessions)
			&& sessions.ValueKind == JsonValueKind.Object
			&& sessions.TryGetProperty(_selectedSid, out state);
	}

	private bool SelectedSessionSupportsCampRuntime()
	{
		return TryGetSelectedRuntimeState(out var state) && state.TryGetProperty("camp_active", out _);
	}

	private void RefreshCampRuntimeStatus()
	{
		if (TryGetSelectedRuntimeState(out var state))
		{
			ApplyCampRuntimeStatus(state);
		}
	}

	private void ApplyCampRuntimeStatus(JsonElement state)
	{
		if (!state.TryGetProperty("camp_active", out _))
		{
			_campStatus.Text = "Camp unavailable — reload UnifiedCombat addon";
			return;
		}
		if (SessionStateHelper.GetBool(state, "camp_active", false))
		{
			_campStatus.Text = string.Format(
				CultureInfo.InvariantCulture,
				"Zone {0} ({1}, {2}, {3}) [{4}] by {5}",
				SessionStateHelper.GetString(state, "camp_zone_id", "?"),
				SessionStateHelper.GetString(state, "camp_x", "?"),
				SessionStateHelper.GetString(state, "camp_y", "?"),
				SessionStateHelper.GetString(state, "camp_z", "?"),
				SessionStateHelper.GetString(state, "camp_coordinate_mode", "unknown"),
				SessionStateHelper.GetString(state, "camp_set_by", "?")
			);
			return;
		}
		var lastOperation = SessionStateHelper.GetString(state, "camp_last_op", "");
		if (lastOperation != "" && lastOperation != "CAMP_CLEARED")
		{
			_campStatus.Text = "Camp failed: " + lastOperation;
			return;
		}
		_campStatus.Text = "Camp not set";
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

        var name = SelectedPartyName(_pullerCombo);
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

        var name = SelectedPartyName(_fightLeaderCombo);
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

        var name = SelectedPartyName(_partyFollowCombo);
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_party_follow", ["name"] = name });
        UpdatePartyFollowModeWarning(sid);
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
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_repel_hold_ticks", ["value"] = I(_spAnchorInvalidTicks, 5) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_overlap_deadband", ["value"] = N(_spEmergencyMargin, 0.1) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_repel_weight", ["value"] = N(_spSwitchMargin, 0.35) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "spacing_band_deadband", ["value"] = N(_spArrivalTolerance, 0.2) });
        RememberPendingSpacingFromUi(sid);
    }

    private void RememberPendingSpacingFromUi(string sid)
    {
        _pendingSpacingBySid[sid] = (
            _spUsePrediction.Checked,
            (_spBandMin.Text ?? "").Trim(),
            (_spBandMax.Text ?? "").Trim(),
            (_spModelSizeFloor.Text ?? "").Trim(),
            (_spLookahead.Text ?? "").Trim(),
            (_spAnchorInvalidTicks.Text ?? "").Trim(), // repel hold ticks
            (_spEmergencyMargin.Text ?? "").Trim(), // overlap deadband
            (_spSwitchMargin.Text ?? "").Trim(), // repel weight
            (_spArrivalTolerance.Text ?? "").Trim(), // band deadband
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
        string srvRepelHoldTicks,
        string srvOverlapDeadband,
        string srvRepelWeight,
        string srvBandDeadband,
        bool pendUsePrediction,
        string pendBandMin,
        string pendBandMax,
        string pendModelSizeFloor,
        string pendLookahead,
        string pendRepelHoldTicks,
        string pendOverlapDeadband,
        string pendRepelWeight,
        string pendBandDeadband)
    {
        return srvUsePrediction == pendUsePrediction &&
               EquivalentNumericText(srvBandMin, pendBandMin) &&
               EquivalentNumericText(srvBandMax, pendBandMax) &&
               EquivalentNumericText(srvModelSizeFloor, pendModelSizeFloor) &&
               EquivalentNumericText(srvLookahead, pendLookahead) &&
               EquivalentNumericText(srvRepelHoldTicks, pendRepelHoldTicks) &&
               EquivalentNumericText(srvOverlapDeadband, pendOverlapDeadband) &&
               EquivalentNumericText(srvRepelWeight, pendRepelWeight) &&
               EquivalentNumericText(srvBandDeadband, pendBandDeadband);
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
        var repelHoldTicksSrv = SessionStateHelper.GetString(s, "spacing_repel_hold_ticks", "5");
        var overlapDeadbandSrv = SessionStateHelper.GetString(s, "spacing_overlap_deadband", "0.1");
        var repelWeightSrv = SessionStateHelper.GetString(s, "spacing_repel_weight", "0.35");
        var bandDeadbandSrv = SessionStateHelper.GetString(s, "spacing_band_deadband", "0.2");

        if (_spUsePrediction.Focused || _spBandMin.Focused || _spBandMax.Focused || _spModelSizeFloor.Focused || _spLookahead.Focused ||
            _spAnchorInvalidTicks.Focused || _spEmergencyMargin.Focused ||
            _spSwitchMargin.Focused || _spArrivalTolerance.Focused)
        {
            return;
        }

        if (_pendingSpacingBySid.TryGetValue(sid, out var ps))
        {
            var ageSec = (DateTime.UtcNow - ps.ts).TotalSeconds;
            var echoed = SpacingEchoMatches(
                usePredictionSrv, bandMinSrv, bandMaxSrv, modelSizeFloorSrv, lookaheadSrv, repelHoldTicksSrv, overlapDeadbandSrv,
                repelWeightSrv, bandDeadbandSrv,
                ps.usePrediction, ps.bandMin, ps.bandMax, ps.modelSizeFloor, ps.lookahead, ps.repelHoldTicks, ps.overlapDeadband,
                ps.repelWeight, ps.bandDeadband
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
        ApplyNumericTextIfChanged(_spAnchorInvalidTicks, repelHoldTicksSrv);
        ApplyNumericTextIfChanged(_spEmergencyMargin, overlapDeadbandSrv);
        ApplyNumericTextIfChanged(_spSwitchMargin, repelWeightSrv);
        ApplyNumericTextIfChanged(_spArrivalTolerance, bandDeadbandSrv);
    }

	private void RebindNyzulParkingList()
	{
		var selected = _nyzulParkingList.SelectedIndex;
		_nyzulParkingList.Items.Clear();
		for (var i = 0; i < _nyzulParkingOrder.Count; i++)
		{
			_nyzulParkingList.Items.Add($"{i + 1}. {FormatPartyDisplayName(_nyzulParkingOrder[i])}");
		}
		if (_nyzulParkingOrder.Count > 0)
		{
			_nyzulParkingList.SelectedIndex = Math.Clamp(selected, 0, _nyzulParkingOrder.Count - 1);
		}
	}

	private void OnNyzulConfigChanged()
	{
		if (_suppressEvents || string.IsNullOrWhiteSpace(_selectedSid))
		{
			return;
		}
		CaptureWorkingProfileFromUi(_selectedSid);
	}

	private void NyzulParkerAdd()
	{
		var name = SelectedPartyName(_nyzulParkerCombo);
		if (string.IsNullOrWhiteSpace(name))
		{
			return;
		}
		var coordinator = SelectedPartyName(_nyzulCoordinatorCombo);
		var anchor = SelectedPartyName(_nyzulAnchorCombo);
		if (string.Equals(name, coordinator, StringComparison.OrdinalIgnoreCase)
			|| string.Equals(name, anchor, StringComparison.OrdinalIgnoreCase)
			|| _nyzulParkingOrder.Any(x => string.Equals(x, name, StringComparison.OrdinalIgnoreCase)))
		{
			return;
		}
		_nyzulParkingOrder.Add(name);
		RebindNyzulParkingList();
		_nyzulParkingList.SelectedIndex = _nyzulParkingOrder.Count - 1;
		OnNyzulConfigChanged();
	}

	private void NyzulParkerRemove()
	{
		var index = _nyzulParkingList.SelectedIndex;
		if (index < 0 || index >= _nyzulParkingOrder.Count)
		{
			return;
		}
		_nyzulParkingOrder.RemoveAt(index);
		RebindNyzulParkingList();
		OnNyzulConfigChanged();
	}

	private void NyzulParkerMove(int delta)
	{
		var index = _nyzulParkingList.SelectedIndex;
		var next = index + delta;
		if (index < 0 || next < 0 || next >= _nyzulParkingOrder.Count)
		{
			return;
		}
		(_nyzulParkingOrder[index], _nyzulParkingOrder[next]) = (_nyzulParkingOrder[next], _nyzulParkingOrder[index]);
		RebindNyzulParkingList();
		_nyzulParkingList.SelectedIndex = next;
		OnNyzulConfigChanged();
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

    private void ApplyDefResurrectionPriority(JsonElement s)
    {
        var configured = SessionStateHelper.SplitOptions(
            s.TryGetProperty("defensive_resurrection_priority", out var priority) ? priority : default
        );
        if (configured.Count == 0)
        {
            configured = new List<string> { "Arise", "Raise III", "Raise II", "Raise" };
        }
        _defResurrectionPriority.BeginUpdate();
        try
        {
            _defResurrectionPriority.Items.Clear();
            foreach (var name in configured.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                _defResurrectionPriority.Items.Add(name);
            }
        }
        finally
        {
            _defResurrectionPriority.EndUpdate();
        }
    }

    private void RefreshDefResurrectionOptions()
    {
        var current = _defResurrectionCombo.SelectedItem?.ToString() ?? "";
        var available = _defResurrectionOptions
            .Where(x => !_defResurrectionPriority.Items.Cast<object>()
                .Any(y => string.Equals(y?.ToString(), x, StringComparison.OrdinalIgnoreCase)))
            .ToList();
        ComboBoxOptionUpdater.ReplaceItemsPreservingTextIfChanged(_defResurrectionCombo, available, current);
        if (_defResurrectionCombo.SelectedIndex < 0 && _defResurrectionCombo.Items.Count > 0)
        {
            _defResurrectionCombo.SelectedIndex = 0;
        }
    }

    private void SendDefResurrectionPriority()
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
        var value = string.Join("|", _defResurrectionPriority.Items.Cast<object>()
            .Select(x => x?.ToString()?.Trim() ?? "")
            .Where(x => x.Length > 0));
        Forward(sid, new Dictionary<string, object?>
        {
            ["op"] = "set",
            ["path"] = "defensive_resurrection_priority",
            ["value"] = value,
        });
    }

    private void AddDefResurrection()
    {
        var name = _defResurrectionCombo.SelectedItem?.ToString()?.Trim() ?? "";
        if (name.Length == 0)
        {
            return;
        }
        if (_defResurrectionPriority.Items.Cast<object>().Any(
            x => string.Equals(x?.ToString(), name, StringComparison.OrdinalIgnoreCase)))
        {
            return;
        }
        _defResurrectionPriority.Items.Add(name);
        _defResurrectionPriority.SelectedIndex = _defResurrectionPriority.Items.Count - 1;
        SendDefResurrectionPriority();
        RefreshDefResurrectionOptions();
    }

    private void RemoveDefResurrection()
    {
        var index = _defResurrectionPriority.SelectedIndex;
        if (index < 0)
        {
            return;
        }
        _defResurrectionPriority.Items.RemoveAt(index);
        if (_defResurrectionPriority.Items.Count > 0)
        {
            _defResurrectionPriority.SelectedIndex = Math.Min(index, _defResurrectionPriority.Items.Count - 1);
        }
        SendDefResurrectionPriority();
        RefreshDefResurrectionOptions();
    }

    private void MoveDefResurrection(int delta)
    {
        var index = _defResurrectionPriority.SelectedIndex;
        var next = index + delta;
        if (index < 0 || next < 0 || next >= _defResurrectionPriority.Items.Count)
        {
            return;
        }
        var item = _defResurrectionPriority.Items[index];
        _defResurrectionPriority.Items.RemoveAt(index);
        _defResurrectionPriority.Items.Insert(next, item);
        _defResurrectionPriority.SelectedIndex = next;
        SendDefResurrectionPriority();
    }

    private static string CleanStatusRemovalPriority(string raw)
    {
        return string.Join(
            "|",
            (raw ?? "").Split('|')
                .Select(x => x.Trim())
                .Where(x => x.Length > 0)
                .Distinct(StringComparer.OrdinalIgnoreCase)
        );
    }

    private void OnDefThresholdChanged()
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

        int crit = 35, med = 55, overwrite = 150, healMinTier = 3, healMaxTier = 4, healMinMissingHp = 250;
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
        try
        {
            healMinTier = (int)Math.Clamp(int.Parse((_defHealMinTier.Text ?? "").Trim()), 1, 6);
        }
        catch
        {
            /* keep default */
        }
        try
        {
            healMaxTier = (int)Math.Clamp(int.Parse((_defHealMaxTier.Text ?? "").Trim()), 1, 6);
        }
        catch
        {
            /* keep default */
        }
        if (healMaxTier < healMinTier)
        {
            healMaxTier = healMinTier;
        }
        try
        {
            healMinMissingHp = (int)Math.Clamp(int.Parse((_defHealMinMissingHp.Text ?? "").Trim()), 0, 5000);
        }
        catch
        {
            /* keep default */
        }
        var ignoreTrusts = _defHealIgnoreTrusts.Checked;
        var curagaMinTargets = decimal.ToInt32(_defCuragaMinTargets.Value);
        var waltzTpReserve = decimal.ToInt32(_defWaltzTpReserve.Value);
        var divineWaltzMinTargets = decimal.ToInt32(_defDivineWaltzMinTargets.Value);
        var naPriority = CleanStatusRemovalPriority(_defNaPriority.Text ?? "");

        if (med < crit)
        {
            med = crit;
        }

        var buffsRaw = _defBuffs.Text ?? "";
        var buffsClean = string.Join(
            "|",
            buffsRaw.Replace(',', '|').Split('|').Select(x => x.Trim()).Where(x => x.Length > 0)
        );
        var targetedRaw = _defTargetedBuffs.Text ?? "";
        var targetedClean = string.Join(
            "|",
            targetedRaw.Split('|').Select(x => x.Trim()).Where(x => x.Length > 0 && x.Contains(':'))
        );
        var enemyDebuffsRaw = _defEnemyDebuffs.Text ?? "";
        var enemyDebuffsClean = string.Join(
            "|",
            enemyDebuffsRaw.Replace(',', '|').Split('|').Select(x => x.Trim()).Where(x => x.Length > 0)
        );
        _defCrit.Text = crit.ToString();
        _defMed.Text = med.ToString();
        _defHealMinTier.Text = healMinTier.ToString();
        _defHealMaxTier.Text = healMaxTier.ToString();
        _defHealMinMissingHp.Text = healMinMissingHp.ToString();
        _defNaPriority.Text = naPriority;
        _defOverwrite.Text = overwrite.ToString();
        _defBuffs.Text = buffsClean;
        _defTargetedBuffs.Text = targetedClean;
        _defEnemyDebuffs.Text = enemyDebuffsClean;
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_critical_hpp", ["value"] = crit });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_medium_hpp", ["value"] = med });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "def_heal_min_tier_cure", ["value"] = healMinTier });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "def_heal_max_tier_cure", ["value"] = healMaxTier });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "def_heal_min_missing_hp", ["value"] = healMinMissingHp });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "def_heal_ignore_trusts", ["value"] = ignoreTrusts ? "on" : "off" });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_curaga_min_targets", ["value"] = curagaMinTargets });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_waltz_tp_reserve", ["value"] = waltzTpReserve });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_divine_waltz_min_targets", ["value"] = divineWaltzMinTargets });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_na_priority", ["value"] = naPriority });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_overwrite_interval", ["value"] = overwrite });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_buffs", ["value"] = buffsClean });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_targeted_buffs", ["value"] = targetedClean });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_enemy_debuffs", ["value"] = enemyDebuffsClean });
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

    private void NoSkillchainTargetAddByName()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var name = _noSkillchainTargetName.Text.Trim();
        if (name.Length == 0)
        {
            return;
        }
        if (!HasName(_noSkillchainTargetRows, name))
        {
            _noSkillchainTargetRows.Add((NextSlot(_noSkillchainTargetRows), name));
            RebindNoSkillchainTargetListUi();
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "no_skillchain_target_add", ["name"] = name });
    }

    private void NoSkillchainTargetAddCurrent()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }
        Forward(sid, new Dictionary<string, object?> { ["op"] = "no_skillchain_target_add_current" });
    }

    private void NoSkillchainTargetRemove()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }
        var idx = _noSkillchainTargetList.SelectedIndex;
        if (idx < 0 || idx >= _noSkillchainTargetRows.Count)
        {
            return;
        }
        var slot = _noSkillchainTargetRows[idx].Slot;
        _noSkillchainTargetRows.RemoveAt(idx);
        for (var i = 0; i < _noSkillchainTargetRows.Count; i++)
        {
            _noSkillchainTargetRows[i] = (i + 1, _noSkillchainTargetRows[i].Name);
        }
        RebindNoSkillchainTargetListUi();
        Forward(sid, new Dictionary<string, object?>
        {
            ["op"] = "no_skillchain_target_remove",
            ["index"] = slot,
            ["slot"] = slot,
        });
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

    private void SleepSpellSetOnly()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var name = _sleepSpellName.Text.Trim();
        if (name.Length == 0)
        {
            return;
        }

        _sleepSpellRows = [(1, name)];
        RebindSleepSpellListUi();
        _sleepSpellList.SelectedIndex = 0;

        Forward(sid, new Dictionary<string, object?> { ["op"] = "sleep_replace_spells", ["value"] = name });
    }

    private void SleepSpellAddByName()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var name = _sleepSpellName.Text.Trim();
        if (name.Length == 0)
        {
            return;
        }
        if (!HasName(_sleepSpellRows, name))
        {
            _sleepSpellRows.Add((NextSlot(_sleepSpellRows), name));
            RebindSleepSpellListUi();
            _sleepSpellList.SelectedIndex = _sleepSpellRows.Count - 1;
        }

        Forward(sid, new Dictionary<string, object?> { ["op"] = "sleep_add_spell", ["name"] = name });
    }

    private void SleepSpellRemove()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var idx = _sleepSpellList.SelectedIndex;
        if (idx < 0)
        {
            return;
        }

        var slot = idx < _sleepSpellRows.Count ? _sleepSpellRows[idx].Slot : SessionStateHelper.ParseTrailingBracketId(_sleepSpellList.Items[idx]?.ToString() ?? "");
        if (!slot.HasValue || slot.Value < 1)
        {
            return;
        }
        if (idx < _sleepSpellRows.Count)
        {
            _sleepSpellRows.RemoveAt(idx);
            for (var i = 0; i < _sleepSpellRows.Count; i++)
            {
                _sleepSpellRows[i] = (i + 1, _sleepSpellRows[i].Name);
            }
            RebindSleepSpellListUi();
        }

        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "sleep_remove_spell",
                ["index"] = slot.Value,
                ["slot"] = slot.Value,
            }
        );
    }

    private void SleepSpellClear()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        _sleepSpellRows = [];
        RebindSleepSpellListUi();
        Forward(sid, new Dictionary<string, object?> { ["op"] = "sleep_replace_spells", ["value"] = "" });
    }

    private void SleepSpellMove(string direction)
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        var idx = _sleepSpellList.SelectedIndex;
        if (idx < 0)
        {
            return;
        }
        var localSlot = idx + 1;
        if (idx < _sleepSpellRows.Count)
        {
            var next = string.Equals(direction, "up", StringComparison.OrdinalIgnoreCase) ? idx - 1 : idx + 1;
            if (next >= 0 && next < _sleepSpellRows.Count)
            {
                (_sleepSpellRows[next], _sleepSpellRows[idx]) = (_sleepSpellRows[idx], _sleepSpellRows[next]);
                for (var i = 0; i < _sleepSpellRows.Count; i++)
                {
                    _sleepSpellRows[i] = (i + 1, _sleepSpellRows[i].Name);
                }
                RebindSleepSpellListUi();
                _sleepSpellList.SelectedIndex = next;
                localSlot = idx + 1;
            }
        }

        int? slot = localSlot;
        if (idx >= _sleepSpellRows.Count)
        {
            slot = SessionStateHelper.ParseTrailingBracketId(_sleepSpellList.Items[idx]?.ToString() ?? "") ?? 0;
        }
        if (!slot.HasValue || slot.Value < 1)
        {
            return;
        }

        Forward(
            sid,
            new Dictionary<string, object?>
            {
                ["op"] = "sleep_move_spell",
                ["index"] = slot.Value,
                ["slot"] = slot.Value,
                ["direction"] = direction,
            }
        );
    }

    private void SaveRemote()
    {
        var sid = RequireSelectedSid();
        if (sid is null)
        {
            return;
        }

        if (!ValidateEncounterConfiguration(out var encounterError))
        {
            SetProfileSaveStatus($"Mirror: profile save blocked ({encounterError})");
            UpdateEncounterUiState();
            return;
        }

        if (!ValidateFormationConfiguration(out var formationError))
        {
            SetProfileSaveStatus($"Mirror: profile save blocked ({formationError})");
            UpdateFormationUiState();
            return;
        }

        _suppressUiSaveOutbound = true;
        try
        {
            JsonObject profile;
            try
            {
                profile = BuildProfileFromUi(sid);
            }
            catch (Exception ex)
            {
                SetProfileSaveStatus($"Mirror: profile save failed ({ex.Message})");
                return;
            }

            if (!TrySaveStructuredProfileV2FromUi(sid, profile, out var v2Error))
            {
                SetProfileSaveStatus($"Mirror: v2 save failed ({v2Error})");
                return;
            }
            _workingProfileBySid[sid] = profile.DeepClone().AsObject();
            MarkActiveActivityProfileSaved(sid);
            SetProfileSaveStatus("Mirror: Profile V2 saved");
        }
        finally
        {
            _suppressUiSaveOutbound = false;
        }
    }

    private void SetProfileSaveStatus(string message)
    {
        statusConnection.Text = message;
        _profileSaveStatusHoldUntilUtc = DateTime.UtcNow.AddSeconds(10);
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

    private void RebindNoSkillchainTargetListUi()
    {
        _noSkillchainTargetList.Items.Clear();
        foreach (var (slot, name) in _noSkillchainTargetRows)
        {
            _noSkillchainTargetList.Items.Add($"{name} [{slot}]");
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

    private void RebindSleepSpellListUi()
    {
        _sleepSpellList.Items.Clear();
        foreach (var (slot, name) in _sleepSpellRows)
        {
            _sleepSpellList.Items.Add($"{name} [{slot}]");
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
        if (!_sessionRunningBySid.TryGetValue(sid, out var running))
        {
            throw new InvalidOperationException($"Runtime engine state is unavailable for session '{sid}'.");
        }
        var wsVal = (_wsCombo.Text ?? "").Trim();
        SendWsUpdate(sid, eng, wsVal);
        var wsMode = WsModeUiToRuntime(_wsModeCombo.SelectedItem?.ToString() ?? "Smart");
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "ws_mode", ["value"] = wsMode });
        Forward(sid, new Dictionary<string, object?>
        {
            ["op"] = "set",
            ["path"] = "weaponskill_allow_aoe",
            ["value"] = _chkWsAllowAoe.Checked,
        });
        Forward(sid, new Dictionary<string, object?>
        {
            ["op"] = "set",
            ["path"] = "fast_skillchain",
            ["value"] = _chkFastSkillchain.Checked,
        });
        Forward(sid, new Dictionary<string, object?>
        {
            ["op"] = "set",
            ["path"] = "skillchain_target",
            ["value"] = SkillchainTargetUiToRuntime(_skillchainTargetCombo.SelectedItem?.ToString()),
        });
        Forward(sid, new Dictionary<string, object?>
        {
            ["op"] = "set",
            ["path"] = "weaponskill_min_tp",
            ["value"] = decimal.ToInt32(_wsMinimumTp.Value),
        });
        SendAbilitiesUpdate();
        Forward(sid, new Dictionary<string, object?> { ["op"] = "ignore_replace_names", ["value"] = string.Join("|", _ignoreRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "partner_replace_names", ["value"] = string.Join("|", _partnerRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "target_ignore_replace_names", ["value"] = string.Join("|", _targetIgnoreRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "no_skillchain_target_replace_names", ["value"] = string.Join("|", _noSkillchainTargetRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "add_priority_replace_names", ["value"] = string.Join("|", _addPriorityRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "sleep_replace_spells", ["value"] = string.Join("|", _sleepSpellRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "path_hunter_replace_names", ["value"] = string.Join("|", _pathHunterRows.Select(r => r.Name)) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "tank_enmity_replace_actions", ["value"] = string.Join("|", _tankEnmityRows) });
        foreach (var key in HubUiConstants.BoolKeys)
        {
            var val = ReadPersistedBoolValue(sid, key, running);
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
        PushDefensiveThresholdsForSid(sid);
        var pull = SelectedPartyName(_pullerCombo);
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_partner", ["slot"] = "puller", ["name"] = pull });
        var fl = SelectedPartyName(_fightLeaderCombo);
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_fight_leader", ["name"] = fl });
        var pf = SelectedPartyName(_partyFollowCombo);
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set_party_follow", ["name"] = pf });
        PushPartyFollowDistances(sid);

        // COR maintenance settings (must be explicitly pushed on full state reapply).
        var corRoll1 = _corRoll1Combo.SelectedItem?.ToString() ?? "";
        var corRoll2 = _corRoll2Combo.SelectedItem?.ToString() ?? "";
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "cor_roll_1", ["value"] = corRoll1 });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "cor_roll_2", ["value"] = corRoll2 });
        var corSlot = _corCrookedRoll1.Checked ? 1 : (_corCrookedRoll2.Checked ? 2 : 0);
        if (_sessionMetaBySid.TryGetValue(sid, out var meta))
        {
            var main = (meta.Job ?? "").ToUpperInvariant();
            var sub = (meta.SubJob ?? "").ToUpperInvariant();
            var subCorOnly = !string.Equals(main, "COR", StringComparison.Ordinal) && string.Equals(sub, "COR", StringComparison.Ordinal);
            if (subCorOnly)
            {
                corSlot = 0;
            }
        }
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "cor_crooked_roll_slot", ["value"] = corSlot.ToString(CultureInfo.InvariantCulture) });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "cor_elevens", ["value"] = _corElevens.Checked ? "on" : "off" });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "cor_luzaf_range_override", ["value"] = _corLuzafRangeOverride.Checked ? "on" : "off" });
        var corRangeNames = _corRangePartyPanel.Controls.OfType<CheckBox>()
            .Where(c => c.Checked)
            .Select(c => c.Tag?.ToString() ?? c.Text)
            .Where(n => !string.IsNullOrWhiteSpace(n))
            .Distinct(StringComparer.OrdinalIgnoreCase);
        Forward(sid, new Dictionary<string, object?> { ["op"] = "cor_roll_range_replace_names", ["value"] = string.Join("|", corRangeNames) });

        UpdateBooleanCardVisuals();
    }

    private void PushDefensiveThresholdsForSid(string sid)
    {
        int crit = 35, med = 55, overwrite = 150, healMinTier = 3, healMaxTier = 4, healMinMissingHp = 250;
        try { crit = (int)Math.Clamp(int.Parse((_defCrit.Text ?? "").Trim()), 1, 99); } catch { }
        try { med = (int)Math.Clamp(int.Parse((_defMed.Text ?? "").Trim()), 1, 99); } catch { }
        try { overwrite = (int)Math.Clamp(int.Parse((_defOverwrite.Text ?? "").Trim()), 10, 1800); } catch { }
        try { healMinTier = (int)Math.Clamp(int.Parse((_defHealMinTier.Text ?? "").Trim()), 1, 6); } catch { }
        try { healMaxTier = (int)Math.Clamp(int.Parse((_defHealMaxTier.Text ?? "").Trim()), 1, 6); } catch { }
        if (healMaxTier < healMinTier) healMaxTier = healMinTier;
        try { healMinMissingHp = (int)Math.Clamp(int.Parse((_defHealMinMissingHp.Text ?? "").Trim()), 0, 5000); } catch { }
        if (med < crit) med = crit;
        var ignoreTrusts = _defHealIgnoreTrusts.Checked;
        var curagaMinTargets = decimal.ToInt32(_defCuragaMinTargets.Value);
        var waltzTpReserve = decimal.ToInt32(_defWaltzTpReserve.Value);
        var divineWaltzMinTargets = decimal.ToInt32(_defDivineWaltzMinTargets.Value);
        var naPriority = CleanStatusRemovalPriority(_defNaPriority.Text ?? "");
        var buffsRaw = _defBuffs.Text ?? "";
        var buffsClean = string.Join(
            "|",
            buffsRaw.Replace(',', '|').Split('|').Select(x => x.Trim()).Where(x => x.Length > 0)
        );
        var targetedRaw = _defTargetedBuffs.Text ?? "";
        var targetedClean = string.Join(
            "|",
            targetedRaw.Split('|').Select(x => x.Trim()).Where(x => x.Length > 0 && x.Contains(':'))
        );
        var enemyDebuffsRaw = _defEnemyDebuffs.Text ?? "";
        var enemyDebuffsClean = string.Join(
            "|",
            enemyDebuffsRaw.Replace(',', '|').Split('|').Select(x => x.Trim()).Where(x => x.Length > 0)
        );

        _defCrit.Text = crit.ToString();
        _defMed.Text = med.ToString();
        _defHealMinTier.Text = healMinTier.ToString();
        _defHealMaxTier.Text = healMaxTier.ToString();
        _defHealMinMissingHp.Text = healMinMissingHp.ToString();
        _defNaPriority.Text = naPriority;
        _defOverwrite.Text = overwrite.ToString();
        _defBuffs.Text = buffsClean;
        _defTargetedBuffs.Text = targetedClean;
        _defEnemyDebuffs.Text = enemyDebuffsClean;

        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_critical_hpp", ["value"] = crit });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_medium_hpp", ["value"] = med });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "def_heal_min_tier_cure", ["value"] = healMinTier });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "def_heal_max_tier_cure", ["value"] = healMaxTier });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "def_heal_min_missing_hp", ["value"] = healMinMissingHp });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "def_heal_ignore_trusts", ["value"] = ignoreTrusts ? "on" : "off" });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_curaga_min_targets", ["value"] = curagaMinTargets });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_waltz_tp_reserve", ["value"] = waltzTpReserve });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_divine_waltz_min_targets", ["value"] = divineWaltzMinTargets });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_na_priority", ["value"] = naPriority });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_overwrite_interval", ["value"] = overwrite });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_buffs", ["value"] = buffsClean });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_targeted_buffs", ["value"] = targetedClean });
        Forward(sid, new Dictionary<string, object?> { ["op"] = "set", ["path"] = "defensive_enemy_debuffs", ["value"] = enemyDebuffsClean });
    }
}
