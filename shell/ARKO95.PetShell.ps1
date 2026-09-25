[CmdletBinding()]
param(
    [string]$ProjectRoot,
    [switch]$NoTopmost,
    [switch]$TestMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Xaml

Import-Module (Join-Path $PSScriptRoot 'Arko95.Operations.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Arko95.Core.psm1') -Force

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
$paths = Get-Arko95ProjectPaths -ProjectRoot $ProjectRoot

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="ArkoWindow"
        Title="ARKO-95 Pet Shell"
        Width="352" Height="612"
        MinWidth="352" MinHeight="612"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ResizeMode="NoResize" ShowInTaskbar="True"
        FontFamily="Segoe UI Variable Display, Segoe UI">
  <Window.Resources>
    <LinearGradientBrush x:Key="PanelBrush" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#F2151B29" Offset="0"/>
      <GradientStop Color="#F20A111D" Offset="0.58"/>
      <GradientStop Color="#F20D2225" Offset="1"/>
    </LinearGradientBrush>
    <LinearGradientBrush x:Key="GoldBrush" StartPoint="0,0" EndPoint="1,0">
      <GradientStop Color="#FFFFD688" Offset="0"/>
      <GradientStop Color="#FFFFA938" Offset="1"/>
    </LinearGradientBrush>
    <Style x:Key="ModeButton" TargetType="Button">
      <Setter Property="Foreground" Value="#FFDCE8E8"/>
      <Setter Property="Background" Value="#2AFFFFFF"/>
      <Setter Property="BorderBrush" Value="#385BE7D6"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="4,5"/>
      <Setter Property="Margin" Value="2"/>
      <Setter Property="FontSize" Value="9.5"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ModeBorder" CornerRadius="10" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="ModeBorder" Property="Background" Value="#405BE7D6"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="ModeBorder" Property="Background" Value="#66FFB449"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="RoundAction" TargetType="Button">
      <Setter Property="Foreground" Value="#FF071319"/>
      <Setter Property="Background" Value="{StaticResource GoldBrush}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border CornerRadius="12" Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="StopAction" TargetType="Button">
      <Setter Property="Foreground" Value="#FFFFF4F4"/>
      <Setter Property="Background" Value="#FF9E2635"/>
      <Setter Property="BorderBrush" Value="#FFFF7E89"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="7,4"/>
      <Setter Property="FontSize" Value="8.5"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="StopBorder" CornerRadius="9" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                    Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="StopBorder" Property="Background" Value="#FFC63346"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="StopBorder" Property="Background" Value="#FF701826"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid Margin="10">
    <Border x:Name="ShellBorder" CornerRadius="30" Background="{StaticResource PanelBrush}"
            BorderBrush="#885BE7D6" BorderThickness="1.2">
      <Border.Effect>
        <DropShadowEffect Color="#FF49E8D1" BlurRadius="28" ShadowDepth="0" Opacity="0.22"/>
      </Border.Effect>
      <Grid Margin="17">
        <Grid.RowDefinitions>
          <RowDefinition Height="38"/>
          <RowDefinition Height="220"/>
          <RowDefinition Height="104"/>
          <RowDefinition Height="42"/>
          <RowDefinition Height="80"/>
          <RowDefinition Height="42"/>
          <RowDefinition Height="32"/>
        </Grid.RowDefinitions>

        <Grid x:Name="DragSurface" Grid.Row="0" Background="Transparent" Cursor="SizeAll">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
            <Ellipse x:Name="StatusDot" Width="9" Height="9" Fill="#FF5BE7D6" Margin="0,0,9,0"/>
            <StackPanel>
              <TextBlock Text="ARKO·95" Foreground="#FFFFD688" FontSize="16" FontWeight="Bold"/>
              <TextBlock Text="P.E.T. / LOCAL HATCH" Foreground="#FF7FA5AB" FontSize="8" FontWeight="SemiBold"/>
            </StackPanel>
          </StackPanel>
          <StackPanel Grid.Column="1" Orientation="Horizontal">
            <Button x:Name="RefreshButton" Content="↻" ToolTip="Refresh local status" Style="{StaticResource ModeButton}" Padding="8,3"/>
            <Button x:Name="MinimizeButton" Content="—" ToolTip="Minimize" Style="{StaticResource ModeButton}" Padding="8,3"/>
            <Button x:Name="CloseButton" Content="×" ToolTip="Close ARKO-95" Style="{StaticResource ModeButton}" Padding="8,3"/>
          </StackPanel>
        </Grid>

        <Border Grid.Row="1" CornerRadius="24" Background="#30000000" BorderBrush="#365BE7D6" BorderThickness="1">
          <Grid ClipToBounds="True">
            <Ellipse x:Name="AuraOuter" Width="186" Height="186" Stroke="#AA5BE7D6" StrokeThickness="1.2"
                     StrokeDashArray="2,7" HorizontalAlignment="Center" VerticalAlignment="Center">
              <Ellipse.RenderTransform>
                <RotateTransform x:Name="AuraRotation" CenterX="93" CenterY="93" Angle="0"/>
              </Ellipse.RenderTransform>
            </Ellipse>
            <Ellipse Width="150" Height="150" Stroke="#88FFB449" StrokeThickness="1.4"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
            <Ellipse Width="118" Height="118" HorizontalAlignment="Center" VerticalAlignment="Center">
              <Ellipse.Fill>
                <RadialGradientBrush>
                  <GradientStop Color="#505BE7D6" Offset="0"/>
                  <GradientStop Color="#000A111D" Offset="1"/>
                </RadialGradientBrush>
              </Ellipse.Fill>
            </Ellipse>
            <Image x:Name="PetImage" Width="205" Height="208" Stretch="Uniform" HorizontalAlignment="Center" VerticalAlignment="Center"
                   SnapsToDevicePixels="True" RenderOptions.BitmapScalingMode="HighQuality"/>
            <Border HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,9" Padding="10,4"
                    Background="#D80A111D" CornerRadius="10" BorderBrush="#405BE7D6" BorderThickness="1">
              <TextBlock x:Name="ModeLabel" Text="MIRROR" Foreground="#FFFFD688" FontSize="9" FontWeight="Bold"/>
            </Border>
          </Grid>
        </Border>

        <Border Grid.Row="2" Margin="0,8,0,0" Padding="10,7" CornerRadius="14" Background="#26FFFFFF">
          <StackPanel>
            <TextBlock x:Name="MissionLine" Text="NETXHQ • R1 • SENSING" Foreground="#FFE9F4F3" FontWeight="SemiBold" FontSize="11"/>
            <TextBlock x:Name="HealthLine" Text="Network 95 status loading…" Foreground="#FF8EAFB3" FontSize="10" Margin="0,3,0,0"/>
            <TextBlock x:Name="CrewLine" Text="CREW READY • 3 READ-ONLY SPECIALISTS • PARENT INTEGRATES" Foreground="#FFFFD688" FontSize="8.5" Margin="0,3,0,0"
                       TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="OpsLine" Text="OPS VP • NOT INITIALIZED • LOW-RISK ONLY" Foreground="#FF72D8C9" FontSize="8.5" Margin="0,3,0,0"
                       TextTrimming="CharacterEllipsis"/>
            <TextBlock x:Name="FocusLine" Text="Awaiting a bounded intention" Foreground="#FFB9C9CA" FontSize="9" Margin="0,2,0,0"
                       TextWrapping="Wrap" MaxHeight="27"/>
          </StackPanel>
        </Border>

        <UniformGrid Grid.Row="3" Columns="5" Margin="0,7,0,0">
          <Button x:Name="MirrorButton" Tag="Mirror" Content="Mirror" Style="{StaticResource ModeButton}"/>
          <Button x:Name="ForgeButton" Tag="Forge" Content="Forge" Style="{StaticResource ModeButton}"/>
          <Button x:Name="ChallengeButton" Tag="Challenge" Content="Test" Style="{StaticResource ModeButton}"/>
          <Button x:Name="WitnessButton" Tag="Witness" Content="Witness" Style="{StaticResource ModeButton}"/>
          <Button x:Name="RememberButton" Tag="Remember" Content="Remember" Style="{StaticResource ModeButton}"/>
        </UniformGrid>

        <Grid Grid.Row="4" Margin="0,7,0,0">
          <Border CornerRadius="13" Background="#CC080F18" BorderBrush="#385BE7D6" BorderThickness="1">
            <TextBox x:Name="IntentBox" Background="Transparent" BorderThickness="0" Foreground="#FFF0F5F4"
                     CaretBrush="#FFFFB449" Padding="10,8" FontSize="11" TextWrapping="Wrap"
                     AcceptsReturn="True" MaxLength="500" VerticalScrollBarVisibility="Auto"
                     ToolTip="Describe what you want help with. Do not enter passwords, keys, or tokens."/>
          </Border>
          <TextBlock x:Name="IntentHint" Text="State an outcome — ARKO-95 plans a bounded specialist crew."
                     Foreground="#FF6E8B91" FontSize="10" Margin="11,9" IsHitTestVisible="False"/>
        </Grid>

        <Grid Grid.Row="5" Margin="0,7,0,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="8"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <Button x:Name="StageButton" Grid.Column="0" Content="Plan specialist crew" Style="{StaticResource RoundAction}"/>
          <Button x:Name="CopyButton" Grid.Column="2" Content="Copy crew handoff" Style="{StaticResource ModeButton}" Padding="12,8"/>
        </Grid>

        <Grid Grid.Row="6" Margin="0,7,0,0">
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="5"/>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="5"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBlock x:Name="ReceiptLine" Grid.Column="0" Text="PROPOSAL ONLY • NO HIDDEN AUTHORITY" Foreground="#FF76969B" FontSize="7.5"
                     FontWeight="SemiBold" VerticalAlignment="Center" TextTrimming="CharacterEllipsis" Margin="0,0,7,0"/>
          <Button x:Name="PauseButton" Grid.Column="1" Content="Aura" ToolTip="Pause or resume aura animation" Style="{StaticResource ModeButton}" Padding="7,4"/>
          <Button x:Name="MissionControlButton" Grid.Column="3" Content="MISSION" ToolTip="Open the whole-team Mission Control dashboard" Style="{StaticResource ModeButton}" Padding="7,4"/>
          <Button x:Name="StopOpsButton" Grid.Column="5" Content="STOP OPS" ToolTip="Latch Operations VP off and revoke its current lease" Style="{StaticResource StopAction}"/>
        </Grid>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$PetImage = $window.FindName('PetImage')
$ModeLabel = $window.FindName('ModeLabel')
$MissionLine = $window.FindName('MissionLine')
$HealthLine = $window.FindName('HealthLine')
$CrewLine = $window.FindName('CrewLine')
$OpsLine = $window.FindName('OpsLine')
$FocusLine = $window.FindName('FocusLine')
$ReceiptLine = $window.FindName('ReceiptLine')
$IntentBox = $window.FindName('IntentBox')
$IntentHint = $window.FindName('IntentHint')
$StageButton = $window.FindName('StageButton')
$CopyButton = $window.FindName('CopyButton')
$PauseButton = $window.FindName('PauseButton')
$MissionControlButton = $window.FindName('MissionControlButton')
$StopOpsButton = $window.FindName('StopOpsButton')
$RefreshButton = $window.FindName('RefreshButton')
$MinimizeButton = $window.FindName('MinimizeButton')
$CloseButton = $window.FindName('CloseButton')
$DragSurface = $window.FindName('DragSurface')
$AuraRotation = $window.FindName('AuraRotation')

$window.Topmost = -not $NoTopmost
$window.Left = [Math]::Max(20, [System.Windows.SystemParameters]::WorkArea.Right - $window.Width - 28)
$window.Top = [Math]::Max(20, [System.Windows.SystemParameters]::WorkArea.Bottom - $window.Height - 28)

$script:Mode = 'Mirror'
$script:FrameIndex = 0
$script:AuraAngle = 0.0
$script:VisualPaused = $false
$script:LatestHandoff = ''
$script:UsingAtlas = $false
$script:AtlasBitmap = $null

$stateMap = @{
    Mirror    = @{ Row = 0; Frames = 6 }
    Forge     = @{ Row = 7; Frames = 6 }
    Challenge = @{ Row = 5; Frames = 8 }
    Witness   = @{ Row = 8; Frames = 6 }
    Remember  = @{ Row = 3; Frames = 4 }
}

function New-Arko95Bitmap {
    param([Parameter(Mandatory)][string]$Path)
    $bitmap = [Windows.Media.Imaging.BitmapImage]::new()
    $bitmap.BeginInit()
    $bitmap.CacheOption = [Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.UriSource = [uri]$Path
    $bitmap.EndInit()
    $bitmap.Freeze()
    return $bitmap
}

function Initialize-Arko95Visual {
    if (Test-Path -LiteralPath $paths.Atlas -PathType Leaf) {
        $script:AtlasBitmap = New-Arko95Bitmap -Path $paths.Atlas
        $script:UsingAtlas = ($script:AtlasBitmap.PixelWidth -eq 1536 -and $script:AtlasBitmap.PixelHeight -eq 2288)
    }
    if (-not $script:UsingAtlas -and (Test-Path -LiteralPath $paths.FallbackImage -PathType Leaf)) {
        $PetImage.Source = New-Arko95Bitmap -Path $paths.FallbackImage
    }
}

function Update-Arko95Frame {
    if (-not $script:UsingAtlas) { return }
    $state = $stateMap[$script:Mode]
    $frame = $script:FrameIndex % $state.Frames
    $rectangle = [Windows.Int32Rect]::new(($frame * 192), ($state.Row * 208), 192, 208)
    $crop = [Windows.Media.Imaging.CroppedBitmap]::new($script:AtlasBitmap, $rectangle)
    $crop.Freeze()
    $PetImage.Source = $crop
    $script:FrameIndex = ($script:FrameIndex + 1) % $state.Frames
}

function Set-Arko95Mode {
    param([Parameter(Mandatory)][ValidateSet('Mirror','Forge','Challenge','Witness','Remember')][string]$Mode)
    $script:Mode = $Mode
    $script:FrameIndex = 0
    $ModeLabel.Text = $Mode.ToUpperInvariant()
    $ReceiptLine.Text = (Get-Arko95ModeDirective -Mode $Mode).ToUpperInvariant()
    try {
        $profile = Get-Arko95DelegationProfile -ProjectRoot $ProjectRoot -Mode $Mode
        $specialistIds = @($profile.Specialists | ForEach-Object { [string]$_.id })
        $toolbelt = Get-Arko95ConnectorRegistry -ProjectRoot $ProjectRoot
        $CrewLine.Text = ('CREW • {0} • {1} GATED TOOLS' -f ($specialistIds -join ' + '), @($toolbelt.connectors).Count).ToUpperInvariant()
    }
    catch {
        $CrewLine.Text = 'CREW UNAVAILABLE • PARENT HOLDS'
    }
    Update-Arko95Frame
}

function Update-Arko95StatusView {
    try {
        $status = Get-Arko95Status -ProjectRoot $ProjectRoot
        $MissionLine.Text = '{0} • {1} • {2}' -f $status.Host, $status.RiskTier.ToUpperInvariant(), $status.MissionStatus.ToUpperInvariant()
        $health = if ($null -eq $status.HealthScore) { 'unknown' } else { '{0} / {1}' -f $status.HealthScore, $status.HealthStatus.ToLowerInvariant() }
        if ($status.HealthStale) { $health += ' (stale)' }
        $memory = if ($null -eq $status.MemoryFreeGb) { 'RAM unknown' } else { '{0} GB RAM free' -f $status.MemoryFreeGb }
        $HealthLine.Text = 'Network 95 {0}  •  {1}  •  {2} GB disk free' -f $health, $memory, $status.DiskFreeGb
        $FocusLine.Text = $status.Focus
        if ($status.AtlasReady -and -not $script:UsingAtlas) { Initialize-Arko95Visual }

        $operations = Get-Arko95OperationsStatus -ProjectRoot $ProjectRoot
        if (-not $operations.Initialized) {
            $OpsLine.Text = 'OPS VP • NOT INITIALIZED • LOW-RISK ONLY'
            $OpsLine.Foreground = '#FF8EAFB3'
        }
        elseif ($operations.KillLatched -or $operations.CircuitState -ne 'closed') {
            $reason = if ([string]::IsNullOrWhiteSpace($operations.KillReason)) { $operations.LastFault } else { $operations.KillReason }
            if ([string]::IsNullOrWhiteSpace($reason)) { $reason = 'owner stop or safety hold' }
            $OpsLine.Text = ('OPS VP • STOPPED • {0}' -f $reason).ToUpperInvariant()
            $OpsLine.Foreground = '#FFFF7E89'
        }
        elseif ($operations.HeartbeatStatus -eq 'resource_hold') {
            $OpsLine.Text = ('OPS VP • RESOURCE HOLD • Q {0} • CHAIN {1}' -f $operations.Queue.pending, $(if ($operations.ReceiptChainValid) { 'OK' } else { 'FAULT' }))
            $OpsLine.Foreground = '#FFFFD688'
        }
        elseif ($operations.Ready) {
            $OpsLine.Text = ('OPS VP • RUNNING R0/R1 • Q {0} • DONE {1} • CHAIN {2}' -f $operations.Queue.pending, $operations.DutiesCompleted, $(if ($operations.ReceiptChainValid) { 'OK' } else { 'FAULT' }))
            $OpsLine.Foreground = '#FF72D8C9'
        }
        else {
            $OpsLine.Text = ('OPS VP • PAUSED • LEASE {0} • CHAIN {1}' -f $operations.LeaseStatus, $(if ($operations.ReceiptChainValid) { 'OK' } else { 'FAULT' })).ToUpperInvariant()
            $OpsLine.Foreground = '#FFFFD688'
        }
    }
    catch {
        $HealthLine.Text = 'Local status unavailable — visual shell remains bounded.'
        $FocusLine.Text = $_.Exception.Message
        $OpsLine.Text = 'OPS VP • STATUS UNAVAILABLE • FAIL CLOSED'
        $OpsLine.Foreground = '#FFFF7E89'
    }
}

$animationTimer = [Windows.Threading.DispatcherTimer]::new()
$animationTimer.Interval = [TimeSpan]::FromMilliseconds(190)
$animationTimer.Add_Tick({
    if (-not $script:VisualPaused) {
        $script:AuraAngle = ($script:AuraAngle + 1.8) % 360
        $AuraRotation.Angle = $script:AuraAngle
        Update-Arko95Frame
    }
})

$statusTimer = [Windows.Threading.DispatcherTimer]::new()
$statusTimer.Interval = [TimeSpan]::FromSeconds(8)
$statusTimer.Add_Tick({ Update-Arko95StatusView })

$IntentBox.Add_TextChanged({ $IntentHint.Visibility = if ($IntentBox.Text.Length -eq 0) { 'Visible' } else { 'Collapsed' } })
$DragSurface.Add_MouseLeftButtonDown({ if ($_.ChangedButton -eq [Windows.Input.MouseButton]::Left) { $window.DragMove() } })
$CloseButton.Add_Click({ $window.Close() })
$MinimizeButton.Add_Click({ $window.WindowState = [Windows.WindowState]::Minimized })
$RefreshButton.Add_Click({ Update-Arko95StatusView })

foreach ($name in @('MirrorButton','ForgeButton','ChallengeButton','WitnessButton','RememberButton')) {
    $button = $window.FindName($name)
    $button.Add_Click({ param($sender, $eventArgs) Set-Arko95Mode -Mode ([string]$sender.Tag) })
}

$StageButton.Add_Click({
    try {
        $proposal = New-Arko95DelegationProposal -ProjectRoot $ProjectRoot -Mode $script:Mode -Intent $IntentBox.Text
        $script:LatestHandoff = $proposal.Handoff
        $IntentBox.Clear()
        Set-Arko95Mode -Mode 'Witness'
        $ReceiptLine.Text = ('CREW PLANNED • {0} SPECIALISTS • NOTHING EXECUTED' -f $proposal.SpecialistCount).ToUpperInvariant()
    }
    catch {
        $ReceiptLine.Text = $_.Exception.Message.ToUpperInvariant()
    }
})

$CopyButton.Add_Click({
    try {
        if ([string]::IsNullOrWhiteSpace($script:LatestHandoff) -and (Test-Path -LiteralPath $paths.LatestPrompt)) {
            $script:LatestHandoff = Get-Content -Raw -LiteralPath $paths.LatestPrompt
        }
        if ([string]::IsNullOrWhiteSpace($script:LatestHandoff)) { throw 'Stage an intention first.' }
        [Windows.Clipboard]::SetText($script:LatestHandoff)
        $ReceiptLine.Text = 'HANDOFF COPIED LOCALLY • NOTHING SENT'
    }
    catch {
        $ReceiptLine.Text = $_.Exception.Message.ToUpperInvariant()
    }
})

$PauseButton.Add_Click({
    $script:VisualPaused = -not $script:VisualPaused
    $PauseButton.Content = if ($script:VisualPaused) { 'Resume' } else { 'Aura' }
    $ReceiptLine.Text = if ($script:VisualPaused) { 'VISUALS PAUSED • STATUS READS CONTINUE' } else { 'VISUALS RESUMED • PROPOSAL ONLY' }
})

$MissionControlButton.Add_Click({
    try {
        $launcher = Join-Path $ProjectRoot 'Launch-ARKO95-MissionControl.vbs'
        if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw 'Mission Control launcher is missing.' }
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = 'wscript.exe'
        $startInfo.Arguments = '"' + $launcher + '"'
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $null = [Diagnostics.Process]::Start($startInfo)
        $ReceiptLine.Text = 'MISSION CONTROL OPENED • AUTHORITATIVE STATE REPLAYED'
    }
    catch { $ReceiptLine.Text = ('MISSION CONTROL ERROR • {0}' -f $_.Exception.Message).ToUpperInvariant() }
})

$StopOpsButton.Add_Click({
    try {
        $null = Stop-Arko95Operations -ProjectRoot $ProjectRoot -Reason 'owner_pressed_stop_operations'
        $ReceiptLine.Text = 'OPERATIONS STOPPED • LEASE REVOKED • KILL LATCHED'
        Update-Arko95StatusView
    }
    catch {
        $ReceiptLine.Text = ('STOP OPS ERROR • {0}' -f $_.Exception.Message).ToUpperInvariant()
        Update-Arko95StatusView
    }
})

$window.Add_Closed({
    $animationTimer.Stop()
    $statusTimer.Stop()
})

Initialize-Arko95Visual
Update-Arko95StatusView
Set-Arko95Mode -Mode 'Mirror'

if ($TestMode) {
    [pscustomobject]@{
        ok = $true
        project_root = $ProjectRoot
        xaml_loaded = $null -ne $window
        atlas_ready = $script:UsingAtlas
        fallback_ready = Test-Path -LiteralPath $paths.FallbackImage
        delegation_ready = (Get-Arko95DelegationProfile -ProjectRoot $ProjectRoot -Mode 'Forge').Specialists.Count -eq 3
        toolbelt_connector_count = @(Get-Arko95ConnectorRegistry -ProjectRoot $ProjectRoot).connectors.Count
        toolbelt_effect = 'routing_hints_only'
        operations_module_loaded = $null -ne (Get-Command Get-Arko95OperationsStatus -ErrorAction SilentlyContinue)
        operations_status_initialized = (Get-Arko95OperationsStatus -ProjectRoot $ProjectRoot).Initialized
        mission_control_ready = $null -ne $MissionControlButton -and (Test-Path -LiteralPath (Join-Path $ProjectRoot 'shell\ARKO95.MissionControl.ps1'))
        stop_control_ready = $null -ne $StopOpsButton
        effect = 'proposal_only'
    } | ConvertTo-Json -Depth 4
    $window.Close()
    return
}

$animationTimer.Start()
$statusTimer.Start()
$null = $window.ShowDialog()
