[CmdletBinding()]
param(
    [string]$ProjectRoot,
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

Import-Module (Join-Path $PSScriptRoot 'Arko95.Core.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Arko95.MissionControl.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Arko95.Operations.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Arko95.DecisionLearning.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Arko95.Agency.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Arko95.Core.psm1') -Force

$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ARKO-95 Mission Control" Width="1480" Height="890" MinWidth="1180" MinHeight="760"
        WindowStartupLocation="CenterScreen" Background="#FF050A12" Foreground="#FFEAF8F7"
        FontFamily="Segoe UI" UseLayoutRounding="True">
  <Window.Resources>
    <LinearGradientBrush x:Key="WindowBrush" StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#FF06111F" Offset="0"/>
      <GradientStop Color="#FF071523" Offset="0.58"/>
      <GradientStop Color="#FF0B101D" Offset="1"/>
    </LinearGradientBrush>
    <SolidColorBrush x:Key="Panel" Color="#CC0B1826"/>
    <SolidColorBrush x:Key="Panel2" Color="#B2122233"/>
    <SolidColorBrush x:Key="Cyan" Color="#FF43E9DE"/>
    <SolidColorBrush x:Key="Gold" Color="#FFFFCC66"/>
    <SolidColorBrush x:Key="Green" Color="#FF58E393"/>
    <SolidColorBrush x:Key="Red" Color="#FFFF7183"/>
    <Style x:Key="PanelBorder" TargetType="Border">
      <Setter Property="Background" Value="{StaticResource Panel}"/>
      <Setter Property="BorderBrush" Value="#5543E9DE"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="12"/>
      <Setter Property="Padding" Value="13"/>
    </Style>
    <Style x:Key="StageBorder" TargetType="Border">
      <Setter Property="Background" Value="#66111F2C"/>
      <Setter Property="BorderBrush" Value="#3343E9DE"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="CornerRadius" Value="10"/>
      <Setter Property="Padding" Value="10"/>
      <Setter Property="Margin" Value="4"/>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Foreground" Value="#FF041014"/>
      <Setter Property="Background" Value="{StaticResource Cyan}"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="14,8"/>
      <Setter Property="Margin" Value="4"/>
      <Setter Property="FontWeight" Value="Bold"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style x:Key="SecondaryButton" TargetType="Button">
      <Setter Property="Foreground" Value="#FFEAF8F7"/>
      <Setter Property="Background" Value="#FF173247"/>
      <Setter Property="BorderBrush" Value="#7757CFC5"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,8"/>
      <Setter Property="Margin" Value="4"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <Style x:Key="StopButton" TargetType="Button" BasedOn="{StaticResource SecondaryButton}">
      <Setter Property="Background" Value="#FF8D2637"/>
      <Setter Property="BorderBrush" Value="#FFFF7183"/>
      <Setter Property="FontWeight" Value="Bold"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#FF07111C"/>
      <Setter Property="Foreground" Value="#FFF0FAF9"/>
      <Setter Property="BorderBrush" Value="#5557CFC5"/>
      <Setter Property="CaretBrush" Value="#FFFFCC66"/>
      <Setter Property="Padding" Value="9"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Background" Value="#FF102536"/>
      <Setter Property="Foreground" Value="#FFF0FAF9"/>
      <Setter Property="Padding" Value="7"/>
    </Style>
    <Style TargetType="ListBox">
      <Setter Property="Background" Value="#5507111C"/>
      <Setter Property="Foreground" Value="#FFDCEBEA"/>
      <Setter Property="BorderThickness" Value="0"/>
    </Style>
  </Window.Resources>

  <Grid Background="{StaticResource WindowBrush}" Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="74"/>
      <RowDefinition Height="118"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="154"/>
    </Grid.RowDefinitions>

    <Grid Grid.Row="0" Margin="4,0,4,8">
      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <StackPanel VerticalAlignment="Center">
        <StackPanel Orientation="Horizontal">
          <TextBlock Text="△  NETWORK-95" Foreground="{StaticResource Cyan}" FontWeight="Bold" FontSize="23"/>
          <TextBlock Text="  /  ARKO-95 MISSION CONTROL" Foreground="#FFF1F8F7" FontWeight="SemiBold" FontSize="21"/>
        </StackPanel>
        <TextBlock Text="ONE OBJECTIVE  ×  ONE STATE  ×  ONE EVIDENCE CHAIN" Foreground="#FF7DA5AD" FontSize="11" Margin="2,4,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="1" HorizontalAlignment="Right" VerticalAlignment="Center">
        <TextBlock x:Name="HeaderState" Text="NO ACTIVE MISSION" Foreground="{StaticResource Gold}" FontWeight="Bold" FontSize="14" HorizontalAlignment="Right"/>
        <TextBlock x:Name="HeaderProof" Text="CHAIN —  •  OPS —" Foreground="#FF8FB7BB" FontSize="11" Margin="0,4,0,0" HorizontalAlignment="Right"/>
      </StackPanel>
    </Grid>

    <UniformGrid Grid.Row="1" Columns="7" Margin="0,0,0,10">
      <Border x:Name="Stage0" Style="{StaticResource StageBorder}"><StackPanel><TextBlock Text="1. INTAKE" FontWeight="Bold" FontSize="12"/><TextBlock Text="Objective + admitted signals" Foreground="#FF8EA7AC" FontSize="9" TextWrapping="Wrap" Margin="0,6,0,0"/></StackPanel></Border>
      <Border x:Name="Stage1" Style="{StaticResource StageBorder}"><StackPanel><TextBlock Text="2. DECOMPOSE" FontWeight="Bold" FontSize="12"/><TextBlock Text="Tasks + success evidence" Foreground="#FF8EA7AC" FontSize="9" TextWrapping="Wrap" Margin="0,6,0,0"/></StackPanel></Border>
      <Border x:Name="Stage2" Style="{StaticResource StageBorder}"><StackPanel><TextBlock Text="3. ROUTE &amp; DELEGATE" FontWeight="Bold" FontSize="12"/><TextBlock Text="Narrow lanes + tool hints" Foreground="#FF8EA7AC" FontSize="9" TextWrapping="Wrap" Margin="0,6,0,0"/></StackPanel></Border>
      <Border x:Name="Stage3" Style="{StaticResource StageBorder}"><StackPanel><TextBlock Text="4. EXECUTE" FontWeight="Bold" FontSize="12"/><TextBlock Text="Five compiled local duties" Foreground="#FF8EA7AC" FontSize="9" TextWrapping="Wrap" Margin="0,6,0,0"/></StackPanel></Border>
      <Border x:Name="Stage4" Style="{StaticResource StageBorder}"><StackPanel><TextBlock Text="5. VERIFY" FontWeight="Bold" FontSize="12"/><TextBlock Text="Independent proof review" Foreground="#FF8EA7AC" FontSize="9" TextWrapping="Wrap" Margin="0,6,0,0"/></StackPanel></Border>
      <Border x:Name="Stage5" Style="{StaticResource StageBorder}"><StackPanel><TextBlock Text="6. PERSIST &amp; LEARN" FontWeight="Bold" FontSize="12"/><TextBlock Text="Receipts + lesson candidates" Foreground="#FF8EA7AC" FontSize="9" TextWrapping="Wrap" Margin="0,6,0,0"/></StackPanel></Border>
      <Border x:Name="Stage6" Style="{StaticResource StageBorder}"><StackPanel><TextBlock Text="7. NOTIFY &amp; PRESENT" FontWeight="Bold" FontSize="12"/><TextBlock Text="Local delta + owner decision" Foreground="#FF8EA7AC" FontSize="9" TextWrapping="Wrap" Margin="0,6,0,0"/></StackPanel></Border>
    </UniformGrid>

    <Grid Grid.Row="2">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="300"/>
        <ColumnDefinition Width="10"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="10"/>
        <ColumnDefinition Width="340"/>
      </Grid.ColumnDefinitions>

      <Border Grid.Column="0" Style="{StaticResource PanelBorder}">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="100"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <TextBlock Text="MISSION QUEUE" Foreground="{StaticResource Cyan}" FontWeight="Bold"/>
          <ListBox x:Name="MissionList" Grid.Row="1" Margin="0,8,0,12"/>
          <TextBlock Grid.Row="2" Text="WHOLE-TEAM LANES" Foreground="{StaticResource Gold}" FontWeight="Bold"/>
          <ListBox x:Name="TeamList" Grid.Row="3" Margin="0,8,0,0"/>
        </Grid>
      </Border>

      <Border Grid.Column="2" Style="{StaticResource PanelBorder}">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="88"/>
            <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Text="OWNER OBJECTIVE" Foreground="{StaticResource Cyan}" FontWeight="Bold"/>
          <TextBlock x:Name="ObjectiveDigest" Grid.Row="1" Text="SHA-256 —" Foreground="#FF6E8D93" FontSize="9" Margin="0,4,0,5"/>
          <TextBox x:Name="ObjectiveInput" Grid.Row="2" TextWrapping="Wrap" AcceptsReturn="True" MaxLength="500"
                   ToolTip="One bounded outcome. Never enter passwords, tokens, or keys."/>
          <Grid Grid.Row="3" Margin="0,12,0,8">
            <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="110"/><ColumnDefinition Width="16"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <TextBlock Text="Mode" VerticalAlignment="Center" Foreground="#FF9DB5B8"/>
            <ComboBox x:Name="ModeCombo" Grid.Column="1" Margin="8,0,0,0" SelectedIndex="1"><ComboBoxItem Content="Mirror"/><ComboBoxItem Content="Forge"/><ComboBoxItem Content="Challenge"/><ComboBoxItem Content="Witness"/><ComboBoxItem Content="Remember"/></ComboBox>
            <TextBlock Grid.Column="3" Text="Safe duty" VerticalAlignment="Center" Foreground="#FF9DB5B8"/>
            <ComboBox x:Name="CapabilityCombo" Grid.Column="4" Margin="8,0,0,0" SelectedIndex="0">
              <ComboBoxItem Content="observe.system_health"/><ComboBoxItem Content="audit.receipt_chain"/><ComboBoxItem Content="verify.delegation_receipt"/><ComboBoxItem Content="report.operations_brief"/><ComboBoxItem Content="maintain.operations_workspace"/>
            </ComboBox>
          </Grid>
          <Border Grid.Row="4" Background="#44050C14" BorderBrush="#3343E9DE" BorderThickness="1" CornerRadius="8" Padding="10">
            <ScrollViewer VerticalScrollBarVisibility="Auto"><TextBlock x:Name="MissionDetail" Text="Stage one objective to build a bounded team plan." TextWrapping="Wrap" Foreground="#FFCFE1E0" FontSize="11"/></ScrollViewer>
          </Border>
          <TextBlock x:Name="ControlBoundary" Grid.Row="5" Margin="0,9,0,0" Text="UI IS A CONTROL SURFACE, NOT AN AUTHORITY SOURCE" Foreground="#FFFFCC66" FontWeight="Bold" FontSize="9"/>
        </Grid>
      </Border>

      <Border Grid.Column="4" Style="{StaticResource PanelBorder}">
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="88"/><RowDefinition Height="Auto"/><RowDefinition Height="150"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <TextBlock Text="PROOF &amp; SYSTEM STATE" Foreground="{StaticResource Cyan}" FontWeight="Bold"/>
          <TextBlock x:Name="ChainDetail" Grid.Row="1" Margin="0,8,0,12" TextWrapping="Wrap" Foreground="#FFCFE1E0"/>
          <TextBlock Grid.Row="2" Text="AI FABRIC  •  25% LEARNING CAP" Foreground="{StaticResource Gold}" FontWeight="Bold"/>
          <TextBlock x:Name="AIFabricDetail" Grid.Row="3" Margin="0,8,0,12" TextWrapping="Wrap" Foreground="#FFCFE1E0" FontSize="10"/>
          <TextBlock Grid.Row="4" Text="OPERATIONS VP" Foreground="{StaticResource Gold}" FontWeight="Bold"/>
          <TextBlock x:Name="OpsDetail" Grid.Row="5" Margin="0,8,0,0" TextWrapping="Wrap" Foreground="#FFCFE1E0"/>
        </Grid>
      </Border>
    </Grid>

    <Border Grid.Row="3" Style="{StaticResource PanelBorder}" Margin="0,10,0,0">
      <Grid>
        <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
        <WrapPanel>
          <Button x:Name="StageMissionButton" Content="1  Stage objective" Style="{StaticResource PrimaryButton}"/>
          <Button x:Name="PlanTeamButton" Content="2–3  Prepare team plan" Style="{StaticResource SecondaryButton}"/>
          <Button x:Name="QueueDutyButton" Content="4  Queue safe local duty" Style="{StaticResource SecondaryButton}"/>
          <Button x:Name="SyncButton" Content="5  Link completed duty" Style="{StaticResource SecondaryButton}"/>
          <Button x:Name="HoldButton" Content="Hold mission" Style="{StaticResource SecondaryButton}"/>
          <Button x:Name="AbortButton" Content="Abort mission" Style="{StaticResource SecondaryButton}"/>
          <Button x:Name="RefreshButton" Content="Refresh proof" Style="{StaticResource SecondaryButton}"/>
          <Button x:Name="RefreshFabricButton" Content="Refresh AI fabric" Style="{StaticResource SecondaryButton}" ToolTip="Observe content-free local package, process, signature, listener, and pet-validation metadata. No chats or credentials."/>
          <Button x:Name="RefreshAgencyButton" Content="Refresh agency map" Style="{StaticResource SecondaryButton}" ToolTip="Foreground metadata-only scan of the explicit agency allowlist. No contents, moves, deletes, uploads, or legal workspace access."/>
          <Button x:Name="StopOpsButton" Content="STOP OPS" Style="{StaticResource StopButton}"/>
        </WrapPanel>
        <Grid Grid.Row="1" Margin="5,8,5,0">
          <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="420"/></Grid.ColumnDefinitions>
          <TextBlock x:Name="ActionStatus" Text="READY • LOCAL ONLY • NOTHING SENT" Foreground="#FF9DC0C2" TextWrapping="Wrap"/>
          <TextBlock Grid.Column="1" Text="AI ADAPTERS: STATUS + PROPOSALS ONLY  •  OWNER: FINAL JUDGMENT" Foreground="#FFFFCC66" FontWeight="Bold" HorizontalAlignment="Right" TextWrapping="Wrap" TextAlignment="Right"/>
        </Grid>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

$names = @('HeaderState','HeaderProof','MissionList','TeamList','ObjectiveDigest','ObjectiveInput','ModeCombo','CapabilityCombo','MissionDetail','ChainDetail','AIFabricDetail','OpsDetail','StageMissionButton','PlanTeamButton','QueueDutyButton','SyncButton','HoldButton','AbortButton','RefreshButton','RefreshFabricButton','RefreshAgencyButton','StopOpsButton','ActionStatus')
foreach ($name in $names) { Set-Variable -Name $name -Value $window.FindName($name) -Scope Script }
$stageBorders = @(0..6 | ForEach-Object { $window.FindName("Stage$_") })
$stageIds = @('intake','decompose','route_delegate','execute','verify','persist_learn','notify_present')
$script:CurrentMission = $null

function Get-SelectedComboText {
    param([Parameter(Mandatory)]$Combo)
    if ($null -eq $Combo.SelectedItem) { return '' }
    return [string]$Combo.SelectedItem.Content
}

function Set-StageVisuals {
    param([AllowNull()]$Mission)
    $currentIndex = if ($null -eq $Mission) { -1 } else { [Array]::IndexOf($stageIds,[string]$Mission.stage) }
    for ($i=0; $i -lt $stageBorders.Count; $i++) {
        $border = $stageBorders[$i]
        if ($i -lt $currentIndex) { $border.Background='#5535B978'; $border.BorderBrush='#AA58E393'; $border.Opacity=0.86 }
        elseif ($i -eq $currentIndex) {
            if ($Mission.status -eq 'held') { $border.Background='#668D6A20'; $border.BorderBrush='#FFFFCC66' }
            else { $border.Background='#6643E9DE'; $border.BorderBrush='#FF43E9DE' }
            $border.Opacity=1
        }
        else { $border.Background='#66111F2C'; $border.BorderBrush='#3343E9DE'; $border.Opacity=0.62 }
    }
}

function Update-MissionControlView {
    try {
        $status = Get-Arko95MissionControlStatus -ProjectRoot $ProjectRoot
        $learning = Get-Arko95DecisionLearningStatus -ProjectRoot $ProjectRoot
        $toolIndex = Get-Arko95UnifiedToolIndex -ProjectRoot $ProjectRoot
        $agency = Get-Arko95AgencyStatus -ProjectRoot $ProjectRoot
        $script:CurrentMission = $status.ActiveMission
        $MissionList.Items.Clear()
        foreach ($mission in @($status.Missions)) {
            $short = ([string]$mission.mission_id).Replace('mission-','').Substring(0,8)
            $null = $MissionList.Items.Add(('{0}  {1}  v{2}  {3}' -f $short,([string]$mission.stage).ToUpperInvariant(),$mission.version,([string]$mission.status).ToUpperInvariant()))
        }
        if ($status.MissionCount -eq 0) { $null = $MissionList.Items.Add('No mission has been staged.') }

        $TeamList.Items.Clear()
        foreach ($lane in @($status.TeamLanes)) {
            $marker = if ($lane.may_execute) { 'EXEC' } elseif ($lane.may_approve) { 'OWNER' } else { 'REVIEW' }
            $null = $TeamList.Items.Add(('{0}  •  {1}' -f ([string]$lane.name).ToUpperInvariant(),$marker))
        }

        if ($null -eq $script:CurrentMission) {
            $HeaderState.Text = 'NO OPEN MISSION • INTAKE READY'
            $learnUsed = if ($null -eq $learning.ActiveCycle) { 0 } else { [int]$learning.ActiveCycle.exploration_used }
            $learnCap = if ($null -eq $learning.ActiveCycle) { 25 } else { [int]$learning.ActiveCycle.exploration_cap_credits }
            $HeaderProof.Text = ('MISSION {0} • DATA {1} • AGENCY {2} • LEARN {3}/{4} • OPS {5}' -f $(if($status.ChainValid){'OK'}else{'FAULT'}),$(if($learning.ChainValid){'OK'}else{'FAULT'}),$(if($agency.ChainValid){'OK'}else{'FAULT'}),$learnUsed,$learnCap,$status.Operations.DesiredState).ToUpperInvariant()
            $ObjectiveDigest.Text = 'SHA-256 —'
            $MissionDetail.Text = "One objective becomes one replayed state and one evidence chain.`n`nStage a bounded outcome. The system will plan three read-only specialists, hold connector use behind live verification, and permit execution only through the five compiled R0/R1 Operations VP duties."
            $ObjectiveInput.IsReadOnly = $false
        }
        else {
            $mission = $script:CurrentMission
            $short = ([string]$mission.mission_id).Replace('mission-','').Substring(0,8)
            $HeaderState.Text = ('MISSION {0} • {1} • {2}' -f $short,$mission.stage,$mission.status).ToUpperInvariant()
            $learnUsed = if ($null -eq $learning.ActiveCycle) { 0 } else { [int]$learning.ActiveCycle.exploration_used }
            $learnCap = if ($null -eq $learning.ActiveCycle) { 25 } else { [int]$learning.ActiveCycle.exploration_cap_credits }
            $HeaderProof.Text = ('MISSION {0} • v{1} • DATA {2} • AGENCY {3} • LEARN {4}/{5} • OPS {6}' -f $(if($status.ChainValid){'OK'}else{'FAULT'}),$mission.version,$(if($learning.ChainValid){'OK'}else{'FAULT'}),$(if($agency.ChainValid){'OK'}else{'FAULT'}),$learnUsed,$learnCap,$status.Operations.DesiredState).ToUpperInvariant()
            $ObjectiveInput.Text = [string]$mission.objective
            $ObjectiveInput.IsReadOnly = $true
            $ObjectiveDigest.Text = 'OBJECTIVE SHA-256  ' + [string]$mission.objective_sha256
            $criteria = @($mission.success_criteria | ForEach-Object { '  ✓ ' + [string]$_ }) -join [Environment]::NewLine
            $MissionDetail.Text = "SUCCESS CRITERIA`n$criteria`n`nMODE  $($mission.mode)`nDELEGATION  $(if($mission.delegation_id){$mission.delegation_id}else{'not prepared'})`nDUTY  $(if($mission.duty_id){$mission.duty_id}else{'not queued'})`nVERIFICATION  $($mission.verification_result)`n`nCurrent stage is derived by replaying the event chain; this screen cannot set it directly."
        }

        Set-StageVisuals -Mission $script:CurrentMission
        $head = if ([string]::IsNullOrWhiteSpace($status.HeadHash)) { '—' } else { $status.HeadHash.Substring(0,16) + '…' }
        $dataHead = if ([string]::IsNullOrWhiteSpace($learning.HeadHash)) { '—' } else { $learning.HeadHash.Substring(0,16) + '…' }
        $ChainDetail.Text = "MISSION  $(if($status.ChainValid){'VALID'}else{'FAULT'}) • $($status.EventCount) events`nMISSION HEAD  $head`nDATA  $(if($learning.ChainValid){'VALID'}else{'FAULT'}) • $($learning.EventCount) events`nDATA HEAD  $dataHead`nLIMIT  one open mission + one shadow cycle"

        $adapterLines = @($learning.Adapters | ForEach-Object { '{0}  {1}' -f ([string]$_.display_name).ToUpperInvariant(),([string]$_.runtime_state).ToUpperInvariant() })
        $budgetLine = if ($null -eq $learning.ActiveCycle) { 'LEARNING  no open cycle • 25/100 max exploration' } else { 'LEARNING  {0}/{1} exploration • {2} remaining' -f $learning.ActiveCycle.exploration_used,$learning.ActiveCycle.exploration_cap_credits,$learning.ActiveCycle.remaining_credits }
        $catalogLine = 'UNIFIED VIEW  {0} • {1} ROUTING + {2} RUNTIME • AUTHORITY NONE' -f $toolIndex.TotalCount,$toolIndex.ConnectorCount,$toolIndex.AdapterCount
        $agencyLine = 'AGENCY  {0} SOURCES • {1} FILES • {2} PROPOSALS • AUTHORITY NONE' -f $agency.SourceCount,$agency.TotalFiles,$agency.BacklogCount
        $AIFabricDetail.Text = ($adapterLines -join [Environment]::NewLine) + [Environment]::NewLine + $budgetLine + [Environment]::NewLine + $catalogLine + [Environment]::NewLine + $agencyLine + [Environment]::NewLine + 'FACTS ≠ INFERENCES ≠ PROJECTIONS'

        $ops = $status.Operations
        $OpsDetail.Text = "STATE  $($ops.DesiredState) • circuit $($ops.CircuitState)`nLEASE  $($ops.LeaseStatus) • absolute $($ops.LeaseTemporalValid) • kill $($ops.KillLatched)`nQUEUE  $($ops.Queue.pending) pending • $($ops.DutiesCompleted) complete`nRECEIPT CHAIN  $($ops.ReceiptChainValid)`nCAPABILITIES  exactly five local R0/R1 handlers"

        $hasMission = $null -ne $script:CurrentMission
        $StageMissionButton.IsEnabled = -not $hasMission
        $PlanTeamButton.IsEnabled = $hasMission -and $script:CurrentMission.stage -eq 'intake' -and $script:CurrentMission.status -eq 'active'
        $QueueDutyButton.IsEnabled = $hasMission -and $script:CurrentMission.stage -eq 'route_delegate' -and $script:CurrentMission.status -eq 'active'
        $SyncButton.IsEnabled = $hasMission -and $script:CurrentMission.stage -eq 'execute' -and $script:CurrentMission.status -eq 'active'
        $HoldButton.IsEnabled = $hasMission -and $script:CurrentMission.status -in @('active','held')
        $HoldButton.Content = if ($hasMission -and $script:CurrentMission.status -eq 'held') { 'Resume mission' } else { 'Hold mission' }
        $AbortButton.IsEnabled = $hasMission
    }
    catch {
        $ActionStatus.Text = ('STATUS FAILED CLOSED • ' + $_.Exception.Message).ToUpperInvariant()
        $ActionStatus.Foreground = '#FFFF7183'
    }
}

$StageMissionButton.Add_Click({
    try {
        $mode = Get-SelectedComboText -Combo $ModeCombo
        $mission = New-Arko95Mission -ProjectRoot $ProjectRoot -Objective $ObjectiveInput.Text -Mode $mode
        $ActionStatus.Text = ('INTAKE SEALED • ' + $mission.MissionId + ' • NO EXECUTION').ToUpperInvariant()
        $ActionStatus.Foreground = '#FF58E393'
        Update-MissionControlView
    } catch { $ActionStatus.Text=('INTAKE HELD • '+$_.Exception.Message).ToUpperInvariant(); $ActionStatus.Foreground='#FFFF7183' }
})

$PlanTeamButton.Add_Click({
    try {
        $mission = $script:CurrentMission
        $planned = Start-Arko95MissionPlan -ProjectRoot $ProjectRoot -MissionId $mission.mission_id -ExpectedVersion $mission.version
        $ActionStatus.Text = ('TEAM PLAN SEALED • {0} SPECIALISTS • RECEIPT {1}…' -f $planned.SpecialistCount,$planned.DelegationReceipt.Substring(0,12)).ToUpperInvariant()
        $ActionStatus.Foreground = '#FF58E393'
        Update-MissionControlView
    } catch { $ActionStatus.Text=('PLAN HELD • '+$_.Exception.Message).ToUpperInvariant(); $ActionStatus.Foreground='#FFFF7183' }
})

$QueueDutyButton.Add_Click({
    try {
        $mission = $script:CurrentMission
        $capability = Get-SelectedComboText -Combo $CapabilityCombo
        $queued = Add-Arko95MissionDuty -ProjectRoot $ProjectRoot -MissionId $mission.mission_id -ExpectedVersion $mission.version -Capability $capability
        $ActionStatus.Text = ('SAFE DUTY QUEUED • {0} • {1}' -f $queued.Capability,$queued.DutyId).ToUpperInvariant()
        $ActionStatus.Foreground = '#FF58E393'
        Update-MissionControlView
    } catch { $ActionStatus.Text=('EXECUTION HELD • '+$_.Exception.Message).ToUpperInvariant(); $ActionStatus.Foreground='#FFFF7183' }
})

$SyncButton.Add_Click({
    try {
        $mission = $script:CurrentMission
        $linked = Sync-Arko95MissionExecution -ProjectRoot $ProjectRoot -MissionId $mission.mission_id -ExpectedVersion $mission.version
        $ActionStatus.Text = ('DUTY LINKED • VERIFY STAGE • RECEIPT {0}…' -f $linked.ReviewReceipt.Substring(0,12)).ToUpperInvariant()
        $ActionStatus.Foreground = '#FF58E393'
        Update-MissionControlView
    } catch { $ActionStatus.Text=('VERIFY HELD • '+$_.Exception.Message).ToUpperInvariant(); $ActionStatus.Foreground='#FFFFCC66' }
})

$HoldButton.Add_Click({
    try {
        $mission = $script:CurrentMission
        $action = if ($mission.status -eq 'held') { 'Resume' } else { 'Hold' }
        $null = Stop-Arko95Mission -ProjectRoot $ProjectRoot -MissionId $mission.mission_id -ExpectedVersion $mission.version -Action $action -Reason 'owner_dashboard_action'
        $ActionStatus.Text = ('MISSION ' + $action + ' RECORDED • STAGE UNCHANGED').ToUpperInvariant()
        $ActionStatus.Foreground = '#FFFFCC66'
        Update-MissionControlView
    } catch { $ActionStatus.Text=('MISSION STATE HELD • '+$_.Exception.Message).ToUpperInvariant(); $ActionStatus.Foreground='#FFFF7183' }
})

$AbortButton.Add_Click({
    try {
        $mission = $script:CurrentMission
        $null = Stop-Arko95Mission -ProjectRoot $ProjectRoot -MissionId $mission.mission_id -ExpectedVersion $mission.version -Action Abort -Reason 'owner_dashboard_abort'
        $ActionStatus.Text = 'MISSION ABORTED • EVIDENCE PRESERVED • NEW INTAKE AVAILABLE'
        $ActionStatus.Foreground = '#FFFFCC66'
        $ObjectiveInput.Clear()
        Update-MissionControlView
    } catch { $ActionStatus.Text=('ABORT HELD • '+$_.Exception.Message).ToUpperInvariant(); $ActionStatus.Foreground='#FFFF7183' }
})

$RefreshButton.Add_Click({ Update-MissionControlView; $ActionStatus.Text='REFRESHED • AUTHORITATIVE STATE REPLAYED'; $ActionStatus.Foreground='#FF9DC0C2' })

$RefreshFabricButton.Add_Click({
    try {
        $observed = Update-Arko95LocalAdapterObservations -ProjectRoot $ProjectRoot
        $ActionStatus.Text = ('AI FABRIC REFRESHED • {0} CONTENT-FREE RECEIPTS • AUTHORITY NONE' -f $observed.ReceiptCount)
        $ActionStatus.Foreground = '#FF58E393'
        Update-MissionControlView
    } catch { $ActionStatus.Text=('AI FABRIC HELD • '+$_.Exception.Message).ToUpperInvariant(); $ActionStatus.Foreground='#FFFF7183' }
})

$RefreshAgencyButton.Add_Click({
    try {
        $scan = Invoke-Arko95AgencyScan -ProjectRoot $ProjectRoot
        $ActionStatus.Text = ('AGENCY MAP SEALED • {0} FILES • {1} PROPOSALS • NO CONTENT READ' -f $scan.Catalog.totals.file_count,$scan.Backlog.item_count).ToUpperInvariant()
        $ActionStatus.Foreground = '#FF58E393'
        Update-MissionControlView
    } catch { $ActionStatus.Text=('AGENCY MAP HELD • '+$_.Exception.Message).ToUpperInvariant(); $ActionStatus.Foreground='#FFFF7183' }
})

$StopOpsButton.Add_Click({
    try {
        $null = Stop-Arko95Operations -ProjectRoot $ProjectRoot -Reason 'owner_pressed_mission_control_stop'
        $ActionStatus.Text = 'OPERATIONS STOPPED • LEASE REVOKED • MISSION EVIDENCE PRESERVED'
        $ActionStatus.Foreground = '#FFFF7183'
        Update-MissionControlView
    } catch { $ActionStatus.Text=('STOP FAILED CLOSED • '+$_.Exception.Message).ToUpperInvariant(); $ActionStatus.Foreground='#FFFF7183' }
})

Update-MissionControlView

if ($TestMode) {
    $status = Get-Arko95MissionControlStatus -ProjectRoot $ProjectRoot
    $learning = Get-Arko95DecisionLearningStatus -ProjectRoot $ProjectRoot
    $toolIndex = Get-Arko95UnifiedToolIndex -ProjectRoot $ProjectRoot
    $agency = Get-Arko95AgencyStatus -ProjectRoot $ProjectRoot
    $openClaw = @($learning.Adapters | Where-Object { $_.adapter_id -eq 'openclaw_companion' })[0]
    [pscustomobject]@{
        ok = $true
        xaml_loaded = $null -ne $window
        stage_count = $stageBorders.Count
        authoritative_replay = $true
        chain_valid = $status.ChainValid
        maximum_open_missions = 1
        openclaw_effect = $openClaw.effect
        adapter_count = @($learning.Adapters).Count
        adapter_authority = $learning.AdapterAuthority
        decision_learning_mode = $learning.Mode
        exploration_cap_percent = $learning.ExplorationCapPercent
        projection_is_authority = $learning.ProjectionIsAuthority
        unified_tool_count = $toolIndex.TotalCount
        unified_tool_authority = $toolIndex.Authority
        agency_chain_valid = $agency.ChainValid
        agency_source_count = $agency.SourceCount
        agency_file_count = $agency.TotalFiles
        agency_backlog_count = $agency.BacklogCount
        agency_authority = $agency.Authority
        agency_content_read = $agency.ContentRead
        agency_refresh_control_ready = $null -ne $RefreshAgencyButton
        operations_capability_count = @($status.AllowedOperationsCapabilities).Count
        stop_control_ready = $null -ne $StopOpsButton
        adapter_refresh_control_ready = $null -ne $RefreshFabricButton
        external_notification_default = $false
    } | ConvertTo-Json -Depth 6
    $window.Close()
    return
}

$refreshTimer = [Windows.Threading.DispatcherTimer]::new()
$refreshTimer.Interval = [TimeSpan]::FromSeconds(10)
$refreshTimer.Add_Tick({ Update-MissionControlView })
$window.Add_Closed({ $refreshTimer.Stop() })
$refreshTimer.Start()
$null = $window.ShowDialog()
