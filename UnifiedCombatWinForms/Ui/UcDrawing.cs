using System.Drawing.Drawing2D;

namespace UnifiedCombatWinForms.Ui;

internal static class UcDrawing
{
    internal static int Scale(Control control, int logicalPixels)
        => (int)Math.Round(logicalPixels * control.DeviceDpi / 96F);

    internal static GraphicsPath CreateRoundedPath(Rectangle bounds, int radius)
    {
        var normalizedRadius = Math.Max(0, Math.Min(radius, Math.Min(bounds.Width, bounds.Height) / 2));
        if (normalizedRadius == 0)
        {
            var rectangle = new GraphicsPath();
            rectangle.AddRectangle(bounds);
            return rectangle;
        }

        var diameter = normalizedRadius * 2;
        var path = new GraphicsPath();
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddArc(bounds.Right - diameter, bounds.Bottom - diameter, diameter, diameter, 0, 90);
        path.AddArc(bounds.Left, bounds.Bottom - diameter, diameter, diameter, 90, 90);
        path.CloseFigure();
        return path;
    }

    internal static GraphicsPath CreateTopRoundedPath(Rectangle bounds, int radius)
    {
        var normalizedRadius = Math.Max(0, Math.Min(radius, Math.Min(bounds.Width / 2, bounds.Height)));
        if (normalizedRadius == 0)
        {
            var rectangle = new GraphicsPath();
            rectangle.AddRectangle(bounds);
            return rectangle;
        }

        var diameter = normalizedRadius * 2;
        var path = new GraphicsPath();
        path.StartFigure();
        path.AddLine(bounds.Left, bounds.Bottom, bounds.Left, bounds.Top + normalizedRadius);
        path.AddArc(bounds.Left, bounds.Top, diameter, diameter, 180, 90);
        path.AddLine(bounds.Left + normalizedRadius, bounds.Top, bounds.Right - normalizedRadius, bounds.Top);
        path.AddArc(bounds.Right - diameter, bounds.Top, diameter, diameter, 270, 90);
        path.AddLine(bounds.Right, bounds.Top + normalizedRadius, bounds.Right, bounds.Bottom);
        path.CloseFigure();
        return path;
    }

    internal static void ApplyRoundedRegion(Control control, int logicalRadius)
    {
        var bounds = new Rectangle(0, 0, control.ClientSize.Width, control.ClientSize.Height);
        if (bounds.Width <= 0 || bounds.Height <= 0)
        {
            return;
        }

        using var path = CreateRoundedPath(bounds, Scale(control, logicalRadius));
        var previous = control.Region;
        control.Region = new Region(path);
        previous?.Dispose();
    }
}
