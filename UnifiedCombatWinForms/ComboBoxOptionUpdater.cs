namespace UnifiedCombatWinForms;

internal static class ComboBoxOptionUpdater
{
    internal static List<string> BuildDisplayOptions(IReadOnlyList<string> availableOptions, string configuredValue)
    {
        var displayOptions = new List<string>(availableOptions);
        if (!string.IsNullOrEmpty(configuredValue) && !displayOptions.Contains(configuredValue))
        {
            displayOptions.Insert(0, configuredValue);
        }

        return displayOptions;
    }

    internal static bool SequenceEqualOrdinal(IReadOnlyList<string> left, IReadOnlyList<string> right)
    {
        if (left.Count != right.Count)
        {
            return false;
        }

        for (var i = 0; i < left.Count; i++)
        {
            if (!string.Equals(left[i], right[i], StringComparison.Ordinal))
            {
                return false;
            }
        }

        return true;
    }

    internal static bool ReplaceItemsPreservingTextIfChanged(
        ComboBox comboBox,
        IReadOnlyList<string> displayOptions,
        string configuredValue
    )
    {
        var currentOptions = comboBox.Items.Cast<string>().ToList();
        if (SequenceEqualOrdinal(currentOptions, displayOptions))
        {
            return false;
        }

        if (comboBox.DroppedDown)
        {
            comboBox.DroppedDown = false;
        }

        comboBox.BeginUpdate();
        try
        {
            comboBox.Items.Clear();
            foreach (var option in displayOptions)
            {
                comboBox.Items.Add(option);
            }

            comboBox.SelectedIndex = -1;
            comboBox.Text = configuredValue;
        }
        finally
        {
            comboBox.EndUpdate();
        }

        return true;
    }
}
