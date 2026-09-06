Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# WPF requires a single-threaded apartment. Configurator.bat passes -STA too;
# this guard keeps a direct launch from failing with an opaque WPF exception.
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne [System.Threading.ApartmentState]::STA) {
  throw 'WPF requires STA mode. Launch Configurator.bat (it starts PowerShell with -STA).'
}

Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$builder = Join-Path $root '_tools_customize.ps1'
$oldNoMain = $env:SLX_NO_MAIN
$env:SLX_NO_MAIN = '1'
. $builder
if ($null -eq $oldNoMain) { Remove-Item Env:SLX_NO_MAIN } else { $env:SLX_NO_MAIN = $oldNoMain }

# ---------------------------------------------------------------------------
#  Theme. WPF controls do NOT inherit the window's Foreground -- their default
#  templates bind to the system control-text brush, which is near-black on this
#  background. Every control type used here is templated or coloured below;
#  anything new needs the same treatment or it renders invisible.
# ---------------------------------------------------------------------------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="CS2 Configurator" Width="1000" Height="780" MinWidth="820" MinHeight="600"
        WindowStartupLocation="CenterScreen" Background="#0B0E14" Foreground="#E6EAF2"
        FontFamily="Segoe UI" UseLayoutRounding="True" TextOptions.TextFormattingMode="Display">
 <Window.Resources>
  <SolidColorBrush x:Key="Bg"      Color="#0B0E14"/>
  <SolidColorBrush x:Key="Card"    Color="#141924"/>
  <SolidColorBrush x:Key="Line"    Color="#222A38"/>
  <SolidColorBrush x:Key="Text"    Color="#E6EAF2"/>
  <SolidColorBrush x:Key="Muted"   Color="#8A94A6"/>
  <SolidColorBrush x:Key="Accent"  Color="#4C8DFF"/>
  <SolidColorBrush x:Key="Field"   Color="#0E121B"/>

  <Style TargetType="TextBlock">
   <Setter Property="Foreground" Value="{StaticResource Text}"/>
   <Setter Property="TextWrapping" Value="Wrap"/>
  </Style>

  <!-- Card: one rounded panel per section -->
  <Style x:Key="CardPanel" TargetType="Border">
   <Setter Property="Background" Value="{StaticResource Card}"/>
   <Setter Property="BorderBrush" Value="{StaticResource Line}"/>
   <Setter Property="BorderThickness" Value="1"/>
   <Setter Property="CornerRadius" Value="12"/>
   <Setter Property="Padding" Value="22,18,22,20"/>
   <Setter Property="Margin" Value="0,0,0,14"/>
  </Style>
  <Style x:Key="CardTitle" TargetType="TextBlock">
   <Setter Property="FontSize" Value="15"/>
   <Setter Property="FontWeight" Value="SemiBold"/>
   <Setter Property="Margin" Value="0,0,0,2"/>
  </Style>
  <Style x:Key="CardHint" TargetType="TextBlock">
   <Setter Property="Foreground" Value="{StaticResource Muted}"/>
   <Setter Property="FontSize" Value="12"/>
   <Setter Property="Margin" Value="0,0,0,14"/>
  </Style>
  <Style x:Key="GroupLabel" TargetType="TextBlock">
   <Setter Property="Foreground" Value="{StaticResource Accent}"/>
   <Setter Property="FontSize" Value="11"/>
   <Setter Property="FontWeight" Value="SemiBold"/>
   <Setter Property="Margin" Value="0,14,0,6"/>
  </Style>

  <!-- CheckBox: custom box, because the stock one is a black glyph here -->
  <Style TargetType="CheckBox">
   <Setter Property="Foreground" Value="{StaticResource Text}"/>
   <Setter Property="Margin" Value="0,6,18,6"/>
   <Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template">
    <Setter.Value>
     <ControlTemplate TargetType="CheckBox">
      <StackPanel Orientation="Horizontal" Background="Transparent">
       <Border x:Name="Box" Width="18" Height="18" CornerRadius="5" VerticalAlignment="Top" Margin="0,1,10,0"
               Background="{StaticResource Field}" BorderBrush="#38445C" BorderThickness="1.4">
        <Path x:Name="Tick" Data="M 3,7 L 6.5,10.5 L 13,3.5" Stroke="#0B0E14" StrokeThickness="2"
              StrokeEndLineCap="Round" StrokeStartLineCap="Round" Visibility="Collapsed"/>
       </Border>
       <ContentPresenter VerticalAlignment="Center"/>
      </StackPanel>
      <ControlTemplate.Triggers>
       <Trigger Property="IsChecked" Value="True">
        <Setter TargetName="Box" Property="Background" Value="{StaticResource Accent}"/>
        <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Accent}"/>
        <Setter TargetName="Tick" Property="Visibility" Value="Visible"/>
       </Trigger>
       <Trigger Property="IsMouseOver" Value="True">
        <Setter TargetName="Box" Property="BorderBrush" Value="{StaticResource Accent}"/>
       </Trigger>
       <Trigger Property="IsEnabled" Value="False">
        <Setter Property="Opacity" Value="0.4"/>
       </Trigger>
      </ControlTemplate.Triggers>
     </ControlTemplate>
    </Setter.Value>
   </Setter>
  </Style>

  <!-- TextBox: rounded dark field -->
  <Style TargetType="TextBox">
   <Setter Property="Foreground" Value="{StaticResource Text}"/>
   <Setter Property="CaretBrush" Value="{StaticResource Text}"/>
   <Setter Property="SelectionBrush" Value="{StaticResource Accent}"/>
   <Setter Property="FontSize" Value="13"/>
   <Setter Property="Padding" Value="9,5"/>
   <Setter Property="Template">
    <Setter.Value>
     <ControlTemplate TargetType="TextBox">
      <Border x:Name="Shell" CornerRadius="7" Background="{StaticResource Field}"
              BorderBrush="#2C3547" BorderThickness="1">
       <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"/>
      </Border>
      <ControlTemplate.Triggers>
       <Trigger Property="IsKeyboardFocused" Value="True">
        <Setter TargetName="Shell" Property="BorderBrush" Value="{StaticResource Accent}"/>
       </Trigger>
       <Trigger Property="IsMouseOver" Value="True">
        <Setter TargetName="Shell" Property="BorderBrush" Value="#3E4A61"/>
       </Trigger>
      </ControlTemplate.Triggers>
     </ControlTemplate>
    </Setter.Value>
   </Setter>
  </Style>

  <!-- Buttons: ghost by default, accent variant for the primary action -->
  <Style TargetType="Button">
   <Setter Property="Foreground" Value="{StaticResource Text}"/>
   <Setter Property="Background" Value="#1B2230"/>
   <Setter Property="BorderBrush" Value="#2C3547"/>
   <Setter Property="FontSize" Value="13"/>
   <Setter Property="Padding" Value="20,10"/>
   <Setter Property="Margin" Value="10,0,0,0"/>
   <Setter Property="Cursor" Value="Hand"/>
   <Setter Property="Template">
    <Setter.Value>
     <ControlTemplate TargetType="Button">
      <Border x:Name="Shell" CornerRadius="8" Background="{TemplateBinding Background}"
              BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1">
       <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" Margin="{TemplateBinding Padding}"/>
      </Border>
      <ControlTemplate.Triggers>
       <Trigger Property="IsMouseOver" Value="True">
        <Setter TargetName="Shell" Property="Opacity" Value="0.85"/>
       </Trigger>
       <Trigger Property="IsPressed" Value="True">
        <Setter TargetName="Shell" Property="Opacity" Value="0.7"/>
       </Trigger>
       <Trigger Property="IsEnabled" Value="False">
        <Setter TargetName="Shell" Property="Opacity" Value="0.45"/>
       </Trigger>
      </ControlTemplate.Triggers>
     </ControlTemplate>
    </Setter.Value>
   </Setter>
  </Style>
  <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
   <Setter Property="Background" Value="{StaticResource Accent}"/>
   <Setter Property="BorderBrush" Value="{StaticResource Accent}"/>
   <Setter Property="Foreground" Value="#08101F"/>
   <Setter Property="FontWeight" Value="SemiBold"/>
  </Style>

  <!-- Slim scrollbar; the stock one is light grey chrome -->
  <Style TargetType="ScrollBar">
   <Setter Property="Width" Value="10"/>
   <Setter Property="Background" Value="Transparent"/>
   <Setter Property="Template">
    <Setter.Value>
     <ControlTemplate TargetType="ScrollBar">
      <Grid Background="Transparent">
       <Track x:Name="PART_Track" IsDirectionReversed="True">
        <Track.Thumb>
         <Thumb>
          <Thumb.Template>
           <ControlTemplate TargetType="Thumb">
            <Border CornerRadius="5" Background="#2F3A4D" Margin="3,0"/>
           </ControlTemplate>
          </Thumb.Template>
         </Thumb>
        </Track.Thumb>
        <Track.IncreaseRepeatButton>
         <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False"/>
        </Track.IncreaseRepeatButton>
        <Track.DecreaseRepeatButton>
         <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False"/>
        </Track.DecreaseRepeatButton>
       </Track>
      </Grid>
     </ControlTemplate>
    </Setter.Value>
   </Setter>
  </Style>
 </Window.Resources>

 <Grid>
  <Grid.RowDefinitions>
   <RowDefinition Height="Auto"/>
   <RowDefinition Height="*"/>
   <RowDefinition Height="Auto"/>
  </Grid.RowDefinitions>

  <!-- header -->
  <Border Padding="34,26,34,20" Background="#0E131C" BorderBrush="{StaticResource Line}" BorderThickness="0,0,0,1">
   <StackPanel>
    <TextBlock Text="CS2 CONFIGURATOR" FontSize="24" FontWeight="Bold"/>
    <TextBlock Text="Pick the features, colours and keys. The tool writes a validated, ready-to-copy config package."
               Foreground="{StaticResource Muted}" FontSize="13" Margin="0,4,0,0"/>
   </StackPanel>
  </Border>

  <ScrollViewer Grid.Row="1" Padding="34,22,26,10" VerticalScrollBarVisibility="Auto">
   <StackPanel>

    <Border Style="{StaticResource CardPanel}">
     <StackPanel>
      <TextBlock Text="Features" Style="{StaticResource CardTitle}"/>
      <TextBlock Text="Each feature is one config module. Anything left out keeps the game's own behaviour."
                 Style="{StaticResource CardHint}"/>
      <Border Background="#101724" BorderBrush="#243043" BorderThickness="1" CornerRadius="9" Padding="14,10" Margin="0,0,0,6">
       <StackPanel>
        <CheckBox Name="MovementOnly" Content="Movement only - null-binds and nothing else"/>
        <TextBlock Text="Ships the null-bind state machine on its own. Everything else is left at the game's defaults, and only the movement keys and mode colours stay configurable."
                   Foreground="{StaticResource Muted}" FontSize="12" Margin="28,0,0,2"/>
       </StackPanel>
      </Border>
      <StackPanel Name="Modules"/>
     </StackPanel>
    </Border>

    <Border Name="ColorCard" Style="{StaticResource CardPanel}">
     <StackPanel>
      <TextBlock Text="Movement HUD colour" Style="{StaticResource CardTitle}"/>
      <TextBlock Text="The HUD repaints itself when you switch movement mode, so the colour tells you which mode is live."
                 Style="{StaticResource CardHint}"/>
      <StackPanel Name="Colors"/>
     </StackPanel>
    </Border>

    <Border Name="GroupCard" Style="{StaticResource CardPanel}">
     <StackPanel>
      <TextBlock Text="Settings groups" Style="{StaticResource CardTitle}"/>
      <TextBlock Text="Blocks of convars in autoexec.cfg. Unticked groups are left at the game's defaults."
                 Style="{StaticResource CardHint}"/>
      <WrapPanel Name="Groups"/>
     </StackPanel>
    </Border>

    <Border Style="{StaticResource CardPanel}">
     <StackPanel>
      <TextBlock Text="Key bindings" Style="{StaticResource CardTitle}"/>
      <TextBlock Text="Grouped by what the key does. Change only what you want moved; leave the rest alone."
                 Style="{StaticResource CardHint}"/>
      <StackPanel Name="Keys"/>
     </StackPanel>
    </Border>

    <Border Style="{StaticResource CardPanel}">
     <StackPanel>
      <TextBlock Text="Output" Style="{StaticResource CardTitle}"/>
      <TextBlock Text="Written to builds\custom, plus custom.zip next to it." Style="{StaticResource CardHint}"/>
      <CheckBox Name="UseAutoexec" IsChecked="True" Content="Include the SLX autoexec.cfg (untick if you already have your own)"/>
      <TextBlock Text="Without it, run  exec core/load  once after copying the core folder."
                 Foreground="{StaticResource Muted}" FontSize="12" Margin="28,2,0,0"/>
     </StackPanel>
    </Border>

   </StackPanel>
  </ScrollViewer>

  <!-- footer -->
  <Border Grid.Row="2" Padding="34,16" Background="#0E131C" BorderBrush="{StaticResource Line}" BorderThickness="0,1,0,0">
   <DockPanel>
    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
     <Button Name="Close" Content="Close"/>
     <Button Name="Build" Content="Generate package" Style="{StaticResource Primary}"/>
    </StackPanel>
    <TextBlock Name="Status" VerticalAlignment="Center" Foreground="{StaticResource Muted}" MaxWidth="620" HorizontalAlignment="Left"/>
   </DockPanel>
  </Border>
 </Grid>
</Window>
'@
$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
function C($n) { $window.FindName($n) }
function Res($n) { $window.FindResource($n) }
function Brush([string]$hex) { (New-Object Windows.Media.BrushConverter).ConvertFromString($hex) }

# ---------------------------------------------------------------------------
#  Features
# ---------------------------------------------------------------------------
$moduleChecks = @{}
foreach ($m in $MODULES) {
  $row = New-Object Windows.Controls.StackPanel
  $cb = New-Object Windows.Controls.CheckBox
  $cb.Content = $m[0]; $cb.Tag = $m[0]; $cb.IsChecked = $true
  $cb.FontWeight = 'SemiBold'; $cb.Margin = '0,8,0,0'
  $desc = New-Object Windows.Controls.TextBlock
  $desc.Text = $UI_MODULE_DESC[$m[0]]
  $desc.Foreground = (Res 'Muted'); $desc.FontSize = 12; $desc.Margin = '28,0,0,4'
  [void]$row.Children.Add($cb); [void]$row.Children.Add($desc)
  [void](C Modules).Children.Add($row); $moduleChecks[$m[0]] = $cb
}

# ---------------------------------------------------------------------------
#  Movement HUD colour -- swatches, not cl_hud_color numbers. The number still
#  goes into the profile; nobody has to know it is 5 for purple.
# ---------------------------------------------------------------------------
$script:hudPick = @{ null = '3'; strict = '5' }
$swatches = @{}
$colorLabels = @{}

#  Raw mode's colour is fixed in the master and is not offered here -- two modes
#  sharing one colour would make the readout useless. Read it rather than
#  hardcode it, so a master that repaints raw takes this with it.
$rawColor = '8'
$m = [regex]::Match((Read-Master 'core\modules\hud.cfg'), 'alias hud_c_raw\s+"cl_hud_color (\d+)"')
if ($m.Success) { $rawColor = $m.Groups[1].Value }
$PICKABLE = @($HUD_COLORS | Where-Object { [string]$_[0] -cne $rawColor })

function Paint-Swatches([string]$mode) {
  foreach ($entry in $swatches[$mode].GetEnumerator()) {
    $sel = ([string]$entry.Key -ceq [string]$script:hudPick[$mode])
    if ($sel) { $entry.Value.BorderBrush = (Res 'Text'); $entry.Value.BorderThickness = '2.5' }
    else      { $entry.Value.BorderBrush = (Brush '#2C3547'); $entry.Value.BorderThickness = '1' }
  }
  $colorLabels[$mode].Text = (Hud-Color-Name $script:hudPick[$mode])
}

foreach ($mode in @(
    @('null',   'Null-bind mode (default HUD colour)', 'the default mode: last key pressed wins'),
    @('strict', 'Strict mode',    'releasing a key gives neutral, not the other direction'))) {
  $id = $mode[0]
  $head = New-Object Windows.Controls.TextBlock
  $head.Text = $mode[1].ToUpperInvariant(); $head.Style = (Res 'GroupLabel')
  [void](C Colors).Children.Add($head)

  $sub = New-Object Windows.Controls.TextBlock
  $sub.Text = $mode[2]; $sub.Foreground = (Res 'Muted'); $sub.FontSize = 12; $sub.Margin = '0,0,0,8'
  [void](C Colors).Children.Add($sub)

  $strip = New-Object Windows.Controls.WrapPanel
  $swatches[$id] = @{}
  foreach ($c in $PICKABLE) {
    $b = New-Object Windows.Controls.Border
    $b.Width = 34; $b.Height = 28; $b.CornerRadius = '7'; $b.Margin = '0,0,8,8'
    $b.Background = (Brush ([string]$c[2])); $b.Cursor = 'Hand'
    $b.ToolTip = ("{0}  (cl_hud_color {1})" -f $c[1], $c[0])
    $b.Tag = @($id, [string]$c[0])
    $b.Add_MouseLeftButtonUp({
      $t = $this.Tag
      $script:hudPick[$t[0]] = $t[1]
      Paint-Swatches $t[0]
    })
    [void]$strip.Children.Add($b)
    $swatches[$id][[string]$c[0]] = $b
  }
  [void](C Colors).Children.Add($strip)

  $lbl = New-Object Windows.Controls.TextBlock
  $lbl.FontSize = 13; $lbl.Margin = '0,0,0,4'
  $colorLabels[$id] = $lbl
  [void](C Colors).Children.Add($lbl)
  Paint-Swatches $id
}


# ---------------------------------------------------------------------------
#  Settings groups
# ---------------------------------------------------------------------------
$groupChecks = @{}
foreach ($g in $GROUPS) {
  $cb = New-Object Windows.Controls.CheckBox
  $cb.Content = $g[0]; $cb.Tag = $g[0]; $cb.IsChecked = $true
  $cb.ToolTip = $g[1]
  [void](C Groups).Children.Add($cb); $groupChecks[$g[0]] = $cb
}

# ---------------------------------------------------------------------------
#  Key bindings, in KEY_GROUPS order: movement first, then combat, HUD, misc.
#  The physical key comes from the master keys.cfg so the UI cannot drift.
# ---------------------------------------------------------------------------
$defaultKeys = @{}
foreach ($line in (Split-Lines (Read-Master 'core\keys.cfg'))) {
  $m = [regex]::Match($line, '^\s*bind\s+"?([^"\s]+)"?\s+"([^"]*)"')
  if ($m.Success) { $defaultKeys[$m.Groups[2].Value] = $m.Groups[1].Value }
}
$keyBoxes = @{}
$keyRows = @{}
$keyHeads = @{}
foreach ($grp in $KEY_GROUPS) {
  $head = New-Object Windows.Controls.TextBlock
  $head.Text = ([string]$grp[0]).ToUpperInvariant(); $head.Style = (Res 'GroupLabel')
  [void](C Keys).Children.Add($head)

  #  Two rows per line: 46 binds in one column is a scroll marathon.
  $wrap = New-Object Windows.Controls.WrapPanel
  foreach ($target in $grp[1]) {
    $rule = $BINDS_BY_TARGET[$target]
    $key = ''
    if ($defaultKeys.ContainsKey($target)) { $key = [string]$defaultKeys[$target] }

    $row = New-Object Windows.Controls.DockPanel
    $row.Width = 372; $row.Margin = '0,0,18,6'; $row.LastChildFill = $false

    $box = New-Object Windows.Controls.TextBox
    $box.Text = $key; $box.Width = 118
    $box.HorizontalContentAlignment = 'Center'
    $box.ToolTip = "bind target: $target"
    [Windows.Controls.DockPanel]::SetDock($box, 'Right')
    [void]$row.Children.Add($box)

    $label = New-Object Windows.Controls.TextBlock
    $label.Text = [string]$rule[3]
    $label.Margin = '0,0,14,0'; $label.VerticalAlignment = 'Center'
    $label.TextTrimming = 'CharacterEllipsis'; $label.TextWrapping = 'NoWrap'
    [Windows.Controls.DockPanel]::SetDock($label, 'Left')
    [void]$row.Children.Add($label)

    [void]$wrap.Children.Add($row)
    $keyBoxes[$target] = $box
    $keyRows[$target] = $row
  }
  [void](C Keys).Children.Add($wrap)
  $keyHeads[[string]$grp[0]] = @($head, [string[]]$grp[1])
}

# ---------------------------------------------------------------------------
#  Enable/disable. A key whose feature is not in the build cannot be remapped,
#  so it greys out instead of sitting there looking configurable.
# ---------------------------------------------------------------------------

#  target -> the feature checkbox that owns it. $null = ships in every build.
#  'hudfile' = lives in hud.cfg, which movement OR radar drags in.
$featureOf = @{}
foreach ($b in $BINDS) {
  $t = [string]$b[0]; $m = $b[1]
  if ($null -eq $m) { $featureOf[$t] = $null }
  elseif ($m -ceq 'hud') { $featureOf[$t] = 'hudfile' }
  else { $featureOf[$t] = [string]$m }
}
#  WASD keeps its bind either way -- movement out means it falls back to
#  +forward/+left/+back/+right on the SAME key, so the remap still applies.
foreach ($w in $WASD) { $featureOf[$w[1]] = $null }
$featureOf['+slx_radar_boost'] = 'radar'
$featureOf['hud_fb_toggle']    = 'movement'

#  Movement only: WASD, both jump keys, and the three null-bind mode keys.
$MV_ONLY_KEYS = @{}
foreach ($t in @('+slx_forward','+slx_left','+slx_back','+slx_right',
                 '+slx_jump','+slx_wheeldown','mv_cycle','mv_toggle','mv_reset')) {
  $MV_ONLY_KEYS[$t] = $true
}

function Set-Live($element, [bool]$on) {
  $element.IsEnabled = $on
  $element.Opacity = $(if ($on) { 1.0 } else { 0.35 })
}

function Key-Live([string]$target) {
  if ([bool](C MovementOnly).IsChecked) { return $MV_ONLY_KEYS.ContainsKey($target) }
  $f = $featureOf[$target]
  if ($null -eq $f) { return $true }
  if ($f -ceq 'hudfile') {
    return ([bool]$moduleChecks['movement'].IsChecked -or [bool]$moduleChecks['radar'].IsChecked)
  }
  return [bool]$moduleChecks[$f].IsChecked
}

$script:savedFeatures = $null
$script:syncing = $false
function Sync-Ui {
  #  This function ticks checkboxes itself, and every tick fires the handler
  #  that called it. Without the guard that is an infinite loop.
  if ($script:syncing) { return }
  $script:syncing = $true
  try { Sync-Ui-Inner } finally { $script:syncing = $false }
}

function Sync-Ui-Inner {
  $mvOnly = [bool](C MovementOnly).IsChecked
  if ($mvOnly) {
    #  Remember what was ticked, so unticking the switch puts it all back.
    if ($null -eq $script:savedFeatures) {
      $script:savedFeatures = @{}
      foreach ($e in $moduleChecks.GetEnumerator()) { $script:savedFeatures[$e.Key] = [bool]$e.Value.IsChecked }
    }
    foreach ($e in $moduleChecks.GetEnumerator()) {
      $e.Value.IsChecked = ($e.Key -ceq 'movement')
      Set-Live $e.Value $false
    }
    foreach ($e in $groupChecks.GetEnumerator()) { $e.Value.IsChecked = $false }
  } elseif ($null -ne $script:savedFeatures) {
    foreach ($e in $moduleChecks.GetEnumerator()) {
      $e.Value.IsChecked = [bool]$script:savedFeatures[$e.Key]
      Set-Live $e.Value $true
    }
    foreach ($e in $groupChecks.GetEnumerator()) { $e.Value.IsChecked = $true }
    $script:savedFeatures = $null
  }
  Set-Live (C GroupCard) (-not $mvOnly)
  Set-Live (C ColorCard) ([bool]$moduleChecks['movement'].IsChecked)
  foreach ($e in $keyRows.GetEnumerator()) { Set-Live $e.Value (Key-Live $e.Key) }
  foreach ($h in $keyHeads.GetEnumerator()) {
    $any = $false
    foreach ($t in $h.Value[1]) { if (Key-Live $t) { $any = $true; break } }
    Set-Live $h.Value[0] $any
  }
}

foreach ($cb in @($moduleChecks.Values)) {
  $cb.Add_Checked({ Sync-Ui }); $cb.Add_Unchecked({ Sync-Ui })
}
(C MovementOnly).Add_Checked({ Sync-Ui })
(C MovementOnly).Add_Unchecked({ Sync-Ui })
Sync-Ui

# ---------------------------------------------------------------------------
#  Build
# ---------------------------------------------------------------------------
function Show-Failure([string[]]$messages) {
  $text = ($messages -join [Environment]::NewLine)
  (C Status).Text = "Build failed: $text"
  (C Status).Foreground = (Brush '#FF8A8A')
  [void][System.Windows.MessageBox]::Show($text, 'Configurator validation/output error', 'OK', 'Error')
}

(C Close).Add_Click({ $window.Close() })
(C Build).Add_Click({
  try {
    $name = 'custom'
    $mods = @($moduleChecks.GetEnumerator() | Where-Object {$_.Value.IsChecked} | ForEach-Object {$_.Key})
    $groups = @($groupChecks.GetEnumerator() | Where-Object {$_.Value.IsChecked} | ForEach-Object {$_.Key})
    $keys = @{}; foreach ($entry in $keyBoxes.GetEnumerator()) { $v=([string]$entry.Value.Text).Trim(); if ($v -and (-not $defaultKeys.ContainsKey($entry.Key) -or $v.ToUpperInvariant() -ne ([string]$defaultKeys[$entry.Key]).ToUpperInvariant())) { $keys[$entry.Key]=$v.ToUpperInvariant() } }
    $colors = @{ null = [string]$script:hudPick['null']; strict = [string]$script:hudPick['strict'] }
    $profile = @{ friend='Custom build'; modules=$mods; groups=$groups; keys=$keys; hud_colors=$colors; use_autoexec=([bool](C UseAutoexec).IsChecked) }
    (C Status).Text = 'Validating and generating...'; (C Status).Foreground = (Res 'Muted')
    (C Build).IsEnabled=$false; $window.Dispatcher.Invoke([action]{}, 'Render')

    # Validate before invoking the writer so every failure is available to the
    # GUI instead of disappearing into the builder's Write-Host output.
    try {
      $preview = Generate $profile
      $failures = Validate-Build $preview['files'] $preview['files_modules']
      if ($failures.Count -gt 0) { Show-Failure ([string[]]$failures); return }
    } catch {
      Show-Failure ([string[]]@("build error: $($_.Exception.Message)")); return
    }

    $stage = 'custom.staging'
    $stagePath = Join-Path (Join-Path $root 'builds') $stage
    if (Test-Path -LiteralPath $stagePath) { Remove-Item -LiteralPath $stagePath -Recurse -Force }
    $rc = Invoke-Build $profile $stage
    if ($rc -ne 0) {
      Show-Failure ([string[]]@("Build writer failed (exit code $rc).", "No final build was replaced. Staging output, if any, is at builds\$stage."))
      return
    }
    $out = Join-Path (Join-Path $root 'builds') $name
    if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
    Move-Item -LiteralPath $stagePath -Destination $out
    $zip = Join-Path (Join-Path $root 'builds') "$name.zip"
    try {
      # Pass literal child paths, not a wildcard, so archive creation remains
      # safe even if the implementation later allows unusual file names.
      $items = @(Get-ChildItem -LiteralPath $out -Force | ForEach-Object { $_.FullName })
      if ($items.Count -eq 0) { throw "output directory is empty: $out" }
      Compress-Archive -Path $items -DestinationPath $zip -Force -ErrorAction Stop
    } catch {
      Show-Failure ([string[]]@("Build files were written, but ZIP creation failed: $($_.Exception.Message)", "Folder: $out")); return
    }
    (C Status).Text = "Done - builds\$name and $name.zip"; (C Status).Foreground = (Brush '#7BD88F')
  } catch { (C Status).Text = $_.Exception.Message; (C Status).Foreground = (Brush '#FF8A8A') } finally { (C Build).IsEnabled=$true }
})
$window.ShowDialog() | Out-Null
