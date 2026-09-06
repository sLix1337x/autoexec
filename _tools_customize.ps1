#  ===========================================================================
#  _tools_customize.ps1 -- PowerShell port of _tools_customize.py
#
#  Build a tailored copy of this config for another machine -- a subset
#  of the modules, their keys, none of the rest. No Python needed; runs
#  on the Windows PowerShell 5.1 every Windows 10/11 machine ships.
#
#      powershell -NoProfile -ExecutionPolicy Bypass -File _tools_customize.ps1
#          interactive
#      ... -File _tools_customize.ps1 --profile builds/bob/profile.json
#      ... -File _tools_customize.ps1 --profile x.json --out other-name
#      CUSTOMIZE.bat                                  double-click launcher
#
#  Output goes to builds/<name>/ next to this script, mirroring csgo/
#  (cfg/autoexec.cfg, cfg/core/...), plus INSTALL.txt and profile.json -- the
#  profile makes any build repeatable and is interchangeable with the .py
#  (same keys, same structure). The writer rmtree's builds/<name>/cfg before
#  writing, so --out is fullpath'd and anything that resolves outside
#  builds/ is refused.
#
#  Every build is validated BEFORE a byte is written: each alias called is
#  defined, each bind target exists, each exec names a file the build ships,
#  key names are ones CS2 knows, no key is bound twice, ASCII only, balanced
#  quotes. A failed build writes nothing.
#  ===========================================================================

#  A validation pass that errors halfway must crash loudly, not skip the
#  remaining checks and write a bad build.
$ErrorActionPreference = 'Stop'

$HERE   = Split-Path -Parent $MyInvocation.MyCommand.Path
$SRC    = Join-Path $HERE "csgo\cfg"
#  The git repo keeps the same eleven files under a differently named folder.
#  Same layout below it, so only the root differs.
if (-not (Test-Path $SRC)) { $SRC = Join-Path $HERE "CS2 Advanced Config" }
$BUILDS = Join-Path $HERE "builds"

#  ---------------------------------------------------------------------------
#  MANIFEST -- every fact the build depends on, as data. Read out of
#  csgo/cfg; if the master changes, change this in the same pass.
#  ---------------------------------------------------------------------------

#  Key names the engine knows, verbatim from slx-config/tools/check.py: a
#  bind to anything else is accepted silently and then never fires.
$KEYS_RE = '^(?i:KP_(\d|DIVIDE|MULTIPLY|MINUS|PLUS|ENTER|DEL)|F\d\d?|' +
           'MOUSE\d|MWHEEL(UP|DOWN)|(UP|DOWN|LEFT|RIGHT)ARROW|' +
           'SPACE|ENTER|BACKSPACE|TAB|CAPSLOCK|ESCAPE|INS|DEL|HOME|' +
           'END|PGUP|PGDN|PAUSE|SHIFT|ALT|CTRL|[A-Z0-9]|scancode\d+|' +
           '`|SEMICOLON)$'

#  What the user picks. These are FEATURES, not files: 'movement' and 'radar'
#  both live in the master's hud.cfg/movement.cfg pair, and Module-Files maps a
#  feature selection onto the .cfg files that have to ship.
#
#  The movement-mode HUD colour is part of movement, not a separate choice --
#  the colour IS the mode readout. Radar boost is the only other thing hud.cfg
#  carries, so it stands on its own.
$MODULES = @(
    @("movement",  "null-bind state machine for W/A/S/D + mode HUD colour"),
    @("crosshair", "ch1..ch7 presets, outline + colour toggles"),
    @("weapons",   "fast bomb/gun drop + quickswitch"),
    @("viewmodel", "eight positions on one cycle key"),
    @("radar",     "radar boost on a hold key")
)
$MODULE_ORDER = @("movement", "crosshair", "weapons", "viewmodel", "radar")

#  The module .cfg files, in the order core/load.cfg execs them (movement LAST:
#  it runs mv_null at load, which reaches into hud.cfg for the colour).
$FILE_ORDER = @("hud", "crosshair", "weapons", "viewmodel", "movement")

#  hud.cfg ships whenever anything in it is wanted. Build-Hud then strips the
#  half that is not: no movement means no mode colour, no radar means no boost.
function Module-Files($sel) {
    $want = @{}
    foreach ($m in $sel) { $want[$m] = $true }
    if ($want.ContainsKey("radar") -or $want.ContainsKey("movement")) { $want["hud"] = $true }
    return @($FILE_ORDER | Where-Object { $want.ContainsKey($_) })
}

#  cl_hud_color, 0..12. Names and swatches are the game's own palette; 3/4/5/8
#  are the four this config verified in game (see HANDOFF section 9.8).
$HUD_COLORS = @(
    @(0,  "Team colour", "#8FA0B5"),
    @(1,  "White",       "#E8ECF2"),
    @(2,  "Bright white","#FFFFFF"),
    @(3,  "Light blue",  "#6EC8F0"),
    @(4,  "Blue",        "#3B6FE0"),
    @(5,  "Purple",      "#A45CE0"),
    @(6,  "Red",         "#E04B4B"),
    @(7,  "Orange",      "#E8873A"),
    @(8,  "Yellow",      "#E8D44A"),
    @(9,  "Green",       "#5DBB63"),
    @(10, "Aqua",        "#4FD6C8"),
    @(11, "Pink",        "#E86FB0"),
    @(12, "Teammate",    "#B0A16F")
)

#  Toggleable convar groups in autoexec.cfg. mouse/perf are whole banner
#  sections; the other five are the // <Title> sub-blocks inside SETTINGS.
$GROUPS = @(
    @("mouse",     "MOUSE section: m_yaw + prediction convars"),
    @("hud",       "HUD convars (radar, colour, scale)"),
    @("crosshair", "crosshair default convars"),
    @("viewmodel", "viewmodel position convars"),
    @("audio",     "audio convars"),
    @("network",   "network convars: interp, rate"),
    @("perf",      "PERFORMANCE/LATENCY section: fps cap, freezecam")
)

#  Every bind in core/keys.cfg, in file order, keyed by TARGET (keys get
#  remapped; the target is what identifies a bind). Fields:
#      target    the quoted bind target, verbatim
#      module    owner. $null = keep always (reg verb or raw command)
#      fallback  replacement target when the owner is excluded; $null = drop.
#                The WASD fallback is CRITICAL: without it a friend who
#                excluded movement cannot move at all.
#      label     one line: remap loop, help.cfg, INSTALL.txt
#      section   help.cfg section (KEYPAD/MOVEMENT/COMBAT/VIEW/MISC)
$BINDS = @(
    @("slot6",$null,$null,"weapon slot 6 (reclaimed)","MISC"),
    @("slot7",$null,$null,"weapon slot 7 (reclaimed)","MISC"),
    @("slot8",$null,$null,"weapon slot 8 (reclaimed)","MISC"),
    @("+attack",$null,$null,"fire","COMBAT"),
    @("+attack2",$null,$null,"ADS","COMBAT"),
    @("+slx_use",$null,$null,"use","COMBAT"),
    @("+slx_dropbomb","weapons",$null,"fast bomb drop","COMBAT"),
    @("+slx_dropgun","weapons",$null,"drop secondary","COMBAT"),
    @("+slx_quickswitch","weapons",$null,"quickswitch: knife tap","KEYPAD"),
    @("+slx_forward","movement","+forward","move forward (null-binds)","MOVEMENT"),
    @("+slx_left","movement","+left","move left (null-binds)","MOVEMENT"),
    @("+slx_back","movement","+back","move back (null-binds)","MOVEMENT"),
    @("+slx_right","movement","+right","move right (null-binds)","MOVEMENT"),
    @("+slx_wheeldown",$null,$null,"jump (scroll down)","MOVEMENT"),
    @("+slx_wheelup",$null,$null,"next weapon (scroll up)","MOVEMENT"),
    @("+slx_duck",$null,$null,"duck","MOVEMENT"),
    @("+slx_jump",$null,$null,"jump","MOVEMENT"),
    @("mv_cycle","movement",$null,"movement mode: null/strict/raw","KEYPAD"),
    @("mv_toggle","movement",$null,"null-binds <-> stock WASD","KEYPAD"),
    @("mv_reset","movement",$null,"PANIC: unstick movement","KEYPAD"),
    @("+slx_decoy",$null,$null,"decoy","COMBAT"),
    @("+slx_smoke",$null,$null,"smoke","COMBAT"),
    @("+slx_he",$null,$null,"HE grenade","COMBAT"),
    @("+slx_molo",$null,$null,"molotov","COMBAT"),
    @("+slx_flash",$null,$null,"flashbang","COMBAT"),
    @("incrementvar cl_radar_scale 0 1 0.25",$null,$null,"radar scale step","VIEW"),
    @("+slx_radar_boost","hud",$null,"radar boost (hold)","VIEW"),
    @("ch_cycle","crosshair",$null,"crosshair cycle","KEYPAD"),
    @("ch_dot","crosshair",$null,"crosshair dot","KEYPAD"),
    @("ch_outline","crosshair",$null,"crosshair outline","KEYPAD"),
    @("hud_fb_toggle","hud",$null,"HUD colour follows mode","KEYPAD"),
    @("ch_color","crosshair",$null,"crosshair colour","VIEW"),
    @("vm_cycle","viewmodel",$null,"viewmodel cycle","VIEW"),
    @("exec core/help",$null,$null,"print this key map","MISC"),
    @("volume 1",$null,$null,"volume max","MISC"),
    @("volume 0.1",$null,$null,"volume low","MISC"),
    @("voice_modenable_toggle",$null,$null,"voice on/off","MISC"),
    @("+voicerecord",$null,$null,"push to talk","COMBAT"),
    @("sensitivity 0.64",$null,$null,"sensitivity 0.64","MISC"),
    @("teammenu",$null,$null,"team menu","MISC"),
    @("toggleconsole",$null,$null,"console","MISC"),
    @("slx_tick","hud",$null,"server tick timing","MISC"),
    @("switchhands",$null,$null,"switch hands","MISC"),
    @("+lookatweapon",$null,$null,"weapon inspect","COMBAT")
)
$BINDS_BY_TARGET = @{}
foreach ($b in $BINDS) { $BINDS_BY_TARGET[$b[0]] = $b }

#  The keys movement.cfg HARDCODES in mv_rl_null/strict/raw, mv_fb_null/
#  strict/raw, mv_off (raw targets) and mv_on. Remapping WASD means patching
#  every one of those sites, not just keys.cfg.
$WASD = @(
    @("w","+slx_forward","+forward"),
    @("a","+slx_left","+left"),
    @("s","+slx_back","+back"),
    @("d","+slx_right","+right")
)
$WASD_VERBS = @{}
foreach ($w in $WASD) { $WASD_VERBS[$w[1]] = $true }

#  Display order for the key list, grouped by what the key is FOR. keys.cfg
#  order is the file's business; this is the order a person reads in. The
#  coverage check below fails the build if a manifest bind is missing here.
$KEY_GROUPS = @(
    @("Movement", @(
        "+slx_forward", "+slx_left", "+slx_back", "+slx_right",
        "+slx_duck", "+slx_jump", "+slx_wheeldown", "+slx_use",
        "+slx_dropbomb", "mv_cycle", "mv_toggle", "mv_reset"
    )),
    @("Combat and equipment", @(
        "+attack", "+attack2", "+slx_quickswitch", "+slx_dropgun",
        "+slx_wheelup", "+slx_flash", "+slx_smoke", "+slx_he", "+slx_molo",
        "+slx_decoy", "+lookatweapon", "slot6", "slot7", "slot8"
    )),
    @("HUD and view", @(
        "hud_fb_toggle", "+slx_radar_boost", "incrementvar cl_radar_scale 0 1 0.25",
        "ch_cycle", "ch_dot", "ch_outline", "ch_color", "vm_cycle"
    )),
    @("Audio, comms and misc", @(
        "+voicerecord", "voice_modenable_toggle", "volume 1", "volume 0.1",
        "sensitivity 0.64", "switchhands", "teammenu", "toggleconsole",
        "slx_tick", "exec core/help"
    ))
)

#  Every bind belongs to exactly one group. A master that gains a bind without
#  a group would silently disappear from the configurator's key list.
$KEY_GROUP_OF = @{}
foreach ($g in $KEY_GROUPS) {
    foreach ($t in $g[1]) {
        if ($KEY_GROUP_OF.ContainsKey($t)) { throw "KEY_GROUPS lists '$t' twice" }
        if (-not $BINDS_BY_TARGET.ContainsKey($t)) { throw "KEY_GROUPS names '$t', which is not a manifest bind" }
        $KEY_GROUP_OF[$t] = $g[0]
    }
}
foreach ($b in $BINDS) {
    if (-not $KEY_GROUP_OF.ContainsKey($b[0])) { throw ("bind '" + $b[0] + "' is in no KEY_GROUPS group") }
}

#  diag.cfg probe layers, in load order: (file, description, marker, module).
$DIAG_LAYERS = @(
    @("core/reg.cfg","the verbs","v_reg",$null),
    @("modules/hud.cfg","radar / mode colour","v_hud","hud"),
    @("modules/crosshair.cfg","presets","v_crosshair","crosshair"),
    @("modules/weapons.cfg","fast drops","v_weapons","weapons"),
    @("modules/viewmodel.cfg","F7 cycle","v_viewmodel","viewmodel"),
    @("modules/movement.cfg","null-binds","v_movement","movement"),
    @("core/keys.cfg","the binds","v_keys",$null)
)

#  Game commands used anywhere in the masters (extracted, not guessed). A
#  single-token call or bind target that is neither a defined alias nor on
#  this list fails the build.
$BUILTIN = @{}
foreach ($w in @(
    "attack","attack2","use","jump","duck","sprint","forward","back","left",
    "right","invnext","lastinv","drop","slot1","slot2","slot3","slot4","slot5",
    "slot6","slot7","slot8","slot9","slot10","voicerecord","lookatweapon",
    "switchhands","teammenu","toggleconsole","voice_modenable_toggle",
    "incrementvar","volume","sensitivity","exec","echo","bind","unbind",
    "alias","toggle","cl_ticktiming","cl_scoreboard_mouse_enable_binding",
    "rightleft","forwardback"
)) { $BUILTIN[$w] = $true }

$BANNER_RE = '^//=+//\s*$'
$BIND_RE   = '^(bind\s+)("?)([A-Za-z0-9_`]+)("?)(\s+)("([^"]*)")(.*)$'
$ALIAS_RE  = '\balias\s+"?([+\-A-Za-z0-9_]+)"?'

$ASCII_ENC = New-Object System.Text.ASCIIEncoding
$UTF8_NB   = New-Object System.Text.UTF8Encoding($false)

#  ---------------------------------------------------------------------------
#  Small helpers
#  ---------------------------------------------------------------------------

function Read-Master([string]$rel) {
    $p = Join-Path $SRC ($rel -replace '/', '\')
    return [System.IO.File]::ReadAllText($p, $ASCII_ENC)
}

function Split-Lines([string]$text) {
    #  Python str.splitlines() for LF text: a trailing newline terminates the
    #  last line, it does not add an empty one.
    $t = $text.Replace("`r`n", "`n").Replace("`r", "`n")
    if ($t.EndsWith("`n")) { $t = $t.Substring(0, $t.Length - 1) }
    if ($t.Length -eq 0) { return [string[]]@() }
    return [string[]]($t -split "`n")
}

function Split-Words([string]$s) {
    #  Python str.split(): whitespace runs, no empty fields. The comma keeps
    #  a one-word result an array (PowerShell would unroll it otherwise).
    if ($s -match '\S') { return ,[string[]]([regex]::Split($s.Trim(), '\s+')) }
    return ,[string[]]@()
}

function Hash-Keys($h) {
    #  $h.Keys is broken in Windows PowerShell 5.1 when any VALUE is itself
    #  a hashtable: enumerating it yields the stringified type name instead
    #  of the keys. GetEnumerator() is reliable.
    $out = New-Object 'System.Collections.Generic.List[string]'
    foreach ($e in $h.GetEnumerator()) { $out.Add([string]$e.Key) }
    return $out.ToArray()
}

function Code-Lines([string]$text) {
    #  (line number, code) with comments and blanks dropped.
    $out = New-Object 'System.Collections.Generic.List[object]'
    $i = 0
    foreach ($l in (Split-Lines $text)) {
        $i++
        $s = $l
        $idx = $s.IndexOf('//')
        if ($idx -ge 0) { $s = $s.Substring(0, $idx) }
        $s = $s.Trim()
        if ($s.Length -gt 0) { $out.Add(@($i, $s)) }
    }
    return ,$out
}

#  ---------------------------------------------------------------------------
#  autoexec.cfg -- settings groups
#  ---------------------------------------------------------------------------

function Build-Autoexec($groups) {
    $text = Read-Master "autoexec.cfg"
    if ($groups.Count -eq $script:GROUPS.Count) { return $text }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in (Split-Lines $text)) { $lines.Add($l) }
    $bstart = {
        param([string]$title)
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim('/', ' ').Trim() -ceq $title) {
                $j = $i - 1
                while ($j -ge 0 -and -not [regex]::IsMatch($lines[$j], $BANNER_RE)) { $j-- }
                if ($j -lt 0) { throw "autoexec: no banner above '$title'" }
                return $j
            }
        }
        throw "autoexec: section '$title' not found -- master changed?"
    }
    $s_mouse = & $bstart "MOUSE"
    $s_set   = & $bstart "SETTINGS"
    $s_perf  = & $bstart "PERFORMANCE / LATENCY"
    $s_core  = & $bstart "CORE"
    $out = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in $lines.GetRange(0, $s_mouse)) { $out.Add($l) }
    if ($groups -contains "mouse") {
        foreach ($l in $lines.GetRange($s_mouse, $s_set - $s_mouse)) { $out.Add($l) }
    }
    #  SETTINGS: banner + kept sub-blocks. Each sub-block runs from its
    #  // <Title> marker to the next marker (or the PERFORMANCE banner).
    $marks = @(
        @("// HUD","hud"), @("// Crosshair","crosshair"),
        @("// Viewmodel","viewmodel"), @("// Audio","audio"),
        @("// Network","network")
    )
    $idx = New-Object 'System.Collections.Generic.List[object]'
    $pos = $s_set
    foreach ($mg in $marks) {
        $mk = $mg[0]; $gid = $mg[1]
        $found = $false
        for ($i = $pos; $i -lt $s_perf; $i++) {
            if ($lines[$i].StartsWith($mk, [StringComparison]::Ordinal)) {
                $idx.Add(@($i, $gid)); $pos = $i + 1; $found = $true; break
            }
        }
        if (-not $found) {
            throw "autoexec SETTINGS block '$mk' not found -- master changed?"
        }
    }
    foreach ($l in $lines.GetRange($s_set, $idx[0][0] - $s_set)) { $out.Add($l) }
    for ($n = 0; $n -lt $idx.Count; $n++) {
        $i = $idx[$n][0]; $gid = $idx[$n][1]
        if ($n + 1 -lt $idx.Count) { $end = $idx[$n + 1][0] } else { $end = $s_perf }
        if ($groups -contains $gid) {
            foreach ($l in $lines.GetRange($i, $end - $i)) { $out.Add($l) }
        }
    }
    if ($groups -contains "perf") {
        foreach ($l in $lines.GetRange($s_perf, $s_core - $s_perf)) { $out.Add($l) }
    }
    foreach ($l in $lines.GetRange($s_core, $lines.Count - $s_core)) { $out.Add($l) }
    return ([string]::Join("`n", $out) + "`n")
}

#  ---------------------------------------------------------------------------
#  core/keys.cfg -- module filtering + remaps
#  ---------------------------------------------------------------------------

function Master-Binds([string]$text) {
    #  (key, target) for every bind in keys.cfg, in file order. Asserts the
    #  manifest covers every one -- a bind it does not know is a build that
    #  would silently get it wrong.
    $out = New-Object 'System.Collections.Generic.List[object]'
    foreach ($l in (Split-Lines $text)) {
        $m = [regex]::Match($l, $BIND_RE)
        if (-not $m.Success) { continue }
        if (-not $BINDS_BY_TARGET.ContainsKey($m.Groups[7].Value)) {
            throw ("keys.cfg binds {0} to '{1}', which the manifest does not know -- master changed?" -f $m.Groups[3].Value, $m.Groups[7].Value)
        }
        $out.Add(@($m.Groups[3].Value, $m.Groups[7].Value))
    }
    return ,$out
}

function Rule-Target($rule, $modules) {
    #  $null = the bind is dropped; otherwise the target it survives with
    #  (the fallback if the owner module is excluded).
    if ($null -ne $rule[1] -and $modules -notcontains $rule[1]) { return $rule[2] }
    return $rule[0]
}

function Rewrite-Bind-Line([string]$line, [string]$newKey, [string]$newTarget) {
    #  Rebuild a bind line, keeping the column alignment where the new
    #  key/target still fit. An unchanged bind returns the line verbatim.
    $m = [regex]::Match($line, $BIND_RE)
    $head    = $m.Groups[1].Value
    $quoted  = $m.Groups[2].Value
    $key     = $m.Groups[3].Value
    $tailq   = $m.Groups[4].Value
    $pad     = $m.Groups[5].Value
    $quotedt = $m.Groups[6].Value
    $target  = $m.Groups[7].Value
    $trailing = $m.Groups[8].Value
    if ($newKey -ceq $key -and $newTarget -ceq $target) { return $line }
    $field = ($head + $quoted + $newKey + $tailq).PadRight(
        $head.Length + $quoted.Length + $key.Length + $tailq.Length + $pad.Length)
    $line = $field + ('"' + $newTarget + '"').PadRight($quotedt.Length) + $trailing
    if ($trailing.Trim().Length -eq 0) { return $line.TrimEnd() }
    return $line
}

function Build-Keys($files, $keymap, $drop) {
    #  @(text, rows) -- rows is @(key, orig_target, final_target, rule) for
    #  every surviving bind, which the remap preview, help.cfg and
    #  INSTALL.txt all read.
    #
    #  $files is the module FILES that ship; $drop names binds whose file ships
    #  but whose feature was not picked (radar boost, the mode-colour toggle).
    if ($null -eq $drop) { $drop = @{} }
    $text = Read-Master "core\keys.cfg"
    $rows = New-Object 'System.Collections.Generic.List[object]'
    if ($files.Count -eq $FILE_ORDER.Count -and $keymap.Count -eq 0 -and $drop.Count -eq 0) {
        foreach ($kt in (Master-Binds $text)) {
            $rows.Add(@($kt[0], $kt[1], $kt[1], $BINDS_BY_TARGET[$kt[1]]))
        }
        return @($text, $rows)
    }
    $out = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in (Split-Lines $text)) {
        $m = [regex]::Match($l, $BIND_RE)
        if (-not $m.Success) { $out.Add($l); continue }
        $key = $m.Groups[3].Value; $target = $m.Groups[7].Value
        if (-not $BINDS_BY_TARGET.ContainsKey($target)) {
            throw ("keys.cfg binds {0} to '{1}', which the manifest does not know -- master changed?" -f $key, $target)
        }
        if ($drop.ContainsKey($target)) { continue }
        $rule = $BINDS_BY_TARGET[$target]
        $final = Rule-Target $rule $files
        if ($null -eq $final) { continue }
        $new = $key
        if ($keymap.ContainsKey($target)) { $new = $keymap[$target] }
        if ($new -ceq "-") { continue }
        $rows.Add(@($new, $target, $final, $rule))
        $out.Add((Rewrite-Bind-Line $l $new $final))
    }
    return @(([string]::Join("`n", $out) + "`n"), $rows)
}

#  ---------------------------------------------------------------------------
#  core/reg.cfg, core/load.cfg, core/diag.cfg
#  ---------------------------------------------------------------------------

function Build-Reg($modules) {
    #  reg ships in every build. When movement is excluded its eight WASD
    #  verbs go too: their bodies call +mv_w/+, which nothing defines any
    #  more, and keys.cfg no longer binds them (WASD falls back to raw).
    $text = Read-Master "core\reg.cfg"
    if ($modules -contains "movement") { return $text }
    $out = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in (Split-Lines $text)) {
        if ([regex]::IsMatch($l, '^alias [+-]slx_(forward|back|left|right)\s')) { continue }
        $out.Add($l)
    }
    return ([string]::Join("`n", $out) + "`n")
}

function Build-Load($files) {
    #  Drop excluded modules' exec lines and fix the echo count. Verbatim when
    #  every module file ships. No stub file exists any more: movement always
    #  drags hud.cfg in with it (Module-Files), so the hud_c_* calls in
    #  movement.cfg can never land on an undefined alias.
    $text = Read-Master "core\load.cfg"
    if ($files.Count -eq $FILE_ORDER.Count) { return $text }
    $out = New-Object 'System.Collections.Generic.List[string]'
    foreach ($l in (Split-Lines $text)) {
        $m = [regex]::Match($l, '^exec core/modules/(\w+)\s*$')
        if ($m.Success -and $files -notcontains $m.Groups[1].Value) { continue }
        if ($l.StartsWith('echo "  [CORE] reg +', [StringComparison]::Ordinal)) {
            $l = 'echo "  [CORE] reg + ' + $files.Count + ' modules loaded"'
        }
        $out.Add($l)
    }
    return ([string]::Join("`n", $out) + "`n")
}

function Build-Diag($files) {
    #  Regenerate the probe with the excluded layers dropped and the x/N
    #  numbering redone, so 'first Unknown command names the failed layer'
    #  stays truthful. Verbatim when every module file is kept.
    $text = Read-Master "core\diag.cfg"
    if ($files.Count -eq $FILE_ORDER.Count) { return $text }
    $layers = @($DIAG_LAYERS | Where-Object { $null -eq $_[3] -or $files -contains $_[3] })
    $n = $layers.Count
    $out = New-Object 'System.Collections.Generic.List[string]'
    $head = Split-Lines $text
    for ($i = 0; $i -lt 10; $i++) { $out.Add($head[$i]) }   # the comment header, verbatim
    $out.Add('echo ""')
    $out.Add('echo "  [diag] ============================================="')
    $out.Add('echo "  [diag] 0/' + $n + '  can this map define aliases at all?"')
    $out.Add('alias v_alive "echo   [diag]      OK -- aliases work here"')
    $out.Add('v_alive')
    $out.Add('echo "  [diag]      no OK above -> WORKSHOP MAP. CS2 blocks ''alias''"')
    $out.Add('echo "  [diag]      there, so nothing below can have loaded."')
    $out.Add('echo "  [diag] ---------------------------------------------"')
    for ($i = 0; $i -lt $layers.Count; $i++) {
        $f = $layers[$i][0]; $desc = $layers[$i][1]; $marker = $layers[$i][2]
        $out.Add('echo "  [diag] ' + ($i + 1) + '/' + $n + '  ' + $f.PadRight(22) + $desc + '"')
        $out.Add($marker)
    }
    $out.Add('echo "  [diag] ---------------------------------------------"')
    $out.Add('echo "  [diag] no ''Unknown command'' above = every layer loaded."')
    $out.Add('echo "  [diag] if 1/' + $n + ' failed, core/load.cfg itself never ran."')
    $out.Add('echo "  [diag] ============================================="')
    $out.Add('echo ""')
    return ([string]::Join("`n", $out) + "`n")
}

#  ---------------------------------------------------------------------------
#  core/help.cfg -- regenerated from the final bind table
#  ---------------------------------------------------------------------------

$HELP_DISP = @{
    "scancode224" = "CTRL"; "scancode53" = "~"; "scancode29" = "Z"
    "scancode27"  = "X";    "scancode6"  = "C"; "scancode25" = "V"
    "scancode43"  = "TAB"
}

function Show-Key([string]$k) {
    $lk = $k.ToLowerInvariant()
    if ($HELP_DISP.ContainsKey($lk)) { return $HELP_DISP[$lk] }
    return $k.ToUpperInvariant()
}

function Build-Help($rows, $modules) {
    #  The static echo keymap goes stale the moment a key moves or a module
    #  is dropped, so non-default builds get it regenerated from the final
    #  bind table -- same echo style and section grouping as the master.
    $out = New-Object 'System.Collections.Generic.List[string]'
    $out.Add('echo ""')
    $out.Add('echo "              [ KEYS ] SLIX1337 CONFIG [ KEYS ]"')
    $out.Add('echo ""')
    $secs = @{}
    foreach ($row in $rows) {
        $key = $row[0]; $rule = $row[3]
        $s = $rule[4]
        if (-not $secs.ContainsKey($s)) {
            $secs[$s] = New-Object 'System.Collections.Generic.List[string]'
        }
        $secs[$s].Add('echo "     ' + (Show-Key $key).PadRight(12) + ' ' + $rule[3].ToUpperInvariant() + '"')
    }
    foreach ($s in @("KEYPAD","MOVEMENT","COMBAT","VIEW","MISC")) {
        if ($secs.ContainsKey($s)) {
            $out.Add('echo "   ' + $s + '"')
            foreach ($x in $secs[$s]) { $out.Add($x) }
            $out.Add('echo ""')
        }
    }
    $out.Add('echo "   CONSOLE"')
    $out.Add('echo "     exec core/diag  -- NAMES THE FIRST LAYER THAT FAILED"')
    $out.Add('echo ""')
    $out.Add('echo "   TROUBLE"')
    if ($modules -contains "movement") {
        $p = $null; $t = $null
        foreach ($row in $rows) { if ($row[1] -ceq "mv_reset")  { $p = $row[0]; break } }
        foreach ($row in $rows) { if ($row[1] -ceq "mv_toggle") { $t = $row[0]; break } }
        if ($null -ne $p) { $out.Add('echo "     STUCK? MASH ' + (Show-Key $p) + ' -- ONE FIX PER PRESS"') }
        if ($null -ne $t) { $out.Add('echo "     ' + (Show-Key $t) + ' -- NULL-BINDS <-> STOCK WASD"') }
    }
    $out.Add('echo "     exec core/diag  -- WHICH LAYER FAILED"')
    $out.Add('echo ""')
    return ([string]::Join("`n", $out) + "`n")
}

#  ---------------------------------------------------------------------------
#  modules/movement.cfg -- patch the hardcoded WASD sites
#  ---------------------------------------------------------------------------

function Build-Movement([string]$text, $keymap) {
    #  mv_rl_*, mv_fb_*, mv_off and mv_on hardcode w/a/s/d. A remapped key
    #  must be patched into every site -- mv_off's raw fallback targets too --
    #  or the ON/OFF toggle silently puts the old keys back.
    $repl = New-Object 'System.Collections.Generic.List[object]'
    foreach ($w in $WASD) {
        $old = $w[0]; $verb = $w[1]; $raw = $w[2]
        $new = $old
        if ($keymap.ContainsKey($verb)) { $new = $keymap[$verb] }
        if ($new -ceq $old) { continue }
        $repl.Add(@("bind $old $verb", "bind $new $verb", 4))
        $repl.Add(@("bind $old $raw",  "bind $new $raw",  1))
    }
    foreach ($r in $repl) {
        $a = $r[0]; $b = $r[1]; $want = $r[2]
        $cnt = [regex]::Matches($text, [regex]::Escape($a)).Count
        if ($cnt -ne $want) {
            throw ("movement.cfg: expected {0} x '{1}', found {2} -- master changed?" -f $want, $a, $cnt)
        }
        $text = $text.Replace($a, $b)
    }
    return $text
}

function Build-Hud([string]$text, $colors, [bool]$radar) {
    #  hud.cfg carries two unrelated things. Radar boost goes when the feature
    #  is not picked; the mode-colour half stays whenever the file ships, since
    #  it only ships for movement or radar and the colour aliases are inert
    #  without the movement module calling them.
    if (-not $radar) {
        $out = New-Object 'System.Collections.Generic.List[string]'
        foreach ($l in (Split-Lines $text)) {
            if ([regex]::IsMatch($l, '^alias\s+[+-]?slx_radar')) { continue }
            $out.Add($l)
        }
        $text = [string]::Join("`n", $out) + "`n"
        $text = $text.Replace('//            MODULE / HUD  --  radar boost, movement-mode colour              //',
                              '//            MODULE / HUD  --  movement-mode colour                           //')
    }
    if ($null -eq $colors) { return $text }
    foreach ($name in @('null','strict')) {
        if (-not $colors.ContainsKey($name)) { continue }
        $v = [string]$colors[$name]
        if (-not $v) { continue }
        if ($v -notmatch '^[0-9]+$' -or [int]$v -gt 12) { throw "hud color '$name' must be an integer from 0 to 12" }
    }
    if ($colors.ContainsKey('null') -and [string]$colors['null']) { $text = $text.Replace('cl_hud_color 3', 'cl_hud_color ' + $colors['null']) }
    if ($colors.ContainsKey('strict') -and [string]$colors['strict']) { $text = $text.Replace('cl_hud_color 5', 'cl_hud_color ' + $colors['strict']) }
    #  The master names the colour in a trailing comment. A build that changed
    #  the number and left "// purple" there would mislead whoever reads it.
    foreach ($mode in @('null','strict')) {
        $text = [regex]::Replace($text, '(?m)^(alias hud_c_' + $mode + '\s+"cl_hud_color (\d+)"\s+)//.*$', {
            param($m)
            $m.Groups[1].Value + '// ' + (Hud-Color-Name $m.Groups[2].Value)
        })
    }
    return $text
}

function Hud-Color-Name($value) {
    foreach ($c in $HUD_COLORS) { if ([string]$c[0] -ceq [string]$value) { return [string]$c[1] } }
    return "colour $value"
}

#  ---------------------------------------------------------------------------
#  Validation -- runs on the whole build before anything is written
#  ---------------------------------------------------------------------------

function Defined-Aliases($files) {
    $out = @{}
    foreach ($f in (Hash-Keys $files)) {
        if (-not $f.EndsWith(".cfg", [StringComparison]::Ordinal)) { continue }
        foreach ($cl in (Code-Lines $files[$f])) {
            foreach ($m in [regex]::Matches($cl[1], $ALIAS_RE)) {
                $out[$m.Groups[1].Value] = $true
            }
        }
    }
    return $out
}

function Test-Aliasish([string]$w) {
    foreach ($p in @("+slx","-slx","+mv","-mv","mv_","vm_","hud_","slx_","v_","ch")) {
        if ($w.StartsWith($p, [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function Validate-Build($files, $modules) {
    #  Fails the build on anything CS2 would swallow silently: a call to an
    #  alias nobody defined, a bind whose target does not exist, an exec of
    #  a file the build does not ship, an invented key name, a doubled-up
    #  key, a non-ASCII byte, an unbalanced quote.
    $fails = New-Object 'System.Collections.Generic.List[string]'
    $defined = Defined-Aliases $files
    $skeys = [string[]](@(Hash-Keys $files))
    [Array]::Sort($skeys, [System.StringComparer]::Ordinal)

    #  bare calls to names that do not exist ---------------------------------
    #  A single-word segment is a call -- unless a quoted argument follows it
    #  (hud_Scaling "0.90" is a convar set, not a call to hud_Scaling).
    foreach ($f in $skeys) {
        if (-not $f.EndsWith(".cfg", [StringComparison]::Ordinal)) { continue }
        foreach ($cl in (Code-Lines $files[$f])) {
            $ln = $cl[0]; $l = $cl[1]
            $parts = [regex]::Split($l, '([;"])')
            $quoted = $false
            for ($j = 0; $j -lt $parts.Count; $j += 2) {
                $seg = $parts[$j]
                $d = ""
                if ($j + 1 -lt $parts.Count) { $d = $parts[$j + 1] }
                $words = Split-Words $seg
                if ($words.Count -eq 1 -and -not (-not $quoted -and $d -ceq '"')) {
                    $w = $words[0]
                    if ((Test-Aliasish $w) -and -not $defined.ContainsKey($w)) {
                        $fails.Add("${f}:${ln} calls $w, which no file in the build defines")
                    }
                }
                if ($d -ceq '"') { $quoted = -not $quoted }
            }
        }
    }

    #  binds: key names, targets, duplicates ---------------------------------
    $scopeRe  = '^bind\s+"?([A-Za-z0-9_`]+)"?\s+"([^"]*)"'
    $inlineRe = '\bbind\s+([A-Za-z0-9_`]+)\s+([^;\"]+)'
    $seen = @{}
    foreach ($f in $skeys) {
        if (-not $f.EndsWith(".cfg", [StringComparison]::Ordinal)) { continue }
        foreach ($cl in (Code-Lines $files[$f])) {
            $ln = $cl[0]; $l = $cl[1]
            $pairs = New-Object 'System.Collections.Generic.List[object]'
            $m = [regex]::Match($l, $scopeRe)
            if ($m.Success) {
                $pairs.Add(@($m.Groups[1].Value, $m.Groups[2].Value, $true))
            } else {
                foreach ($x in [regex]::Matches($l, $inlineRe)) {
                    $pairs.Add(@($x.Groups[1].Value, $x.Groups[2].Value.Trim(), $false))
                }
            }
            foreach ($pr in $pairs) {
                $key = $pr[0]; $target = $pr[1]; $atScope = $pr[2]
                if (-not [regex]::IsMatch($key, $KEYS_RE)) {
                    $fails.Add("${f}:${ln} binds '$key', not a key name the engine knows")
                }
                if ($atScope -and $f -ceq "cfg/core/keys.cfg") {
                    $k = $key.ToLowerInvariant()
                    if ($seen.ContainsKey($k)) {
                        $fails.Add("${f}:${ln} $key is bound twice (also line " + $seen[$k] + ")")
                    }
                    $seen[$k] = $ln
                }
                foreach ($part in $target.Split(';')) {
                    $words = Split-Words $part
                    if ($words.Count -eq 0) { continue }
                    $w = $words[0]
                    if (Test-Aliasish $w) {
                        if (-not $defined.ContainsKey($w)) {
                            $fails.Add("${f}:${ln} binds $key to $w, which is never defined")
                        } elseif ($w.StartsWith("+") -and -not $defined.ContainsKey("-" + $w.Substring(1))) {
                            $fails.Add("${f}:${ln} binds $key to $w, whose release half -" + $w.Substring(1) + " is never defined")
                        }
                    } elseif ($words.Count -eq 1) {
                        if (-not $defined.ContainsKey($w) -and -not $BUILTIN.ContainsKey($w.TrimStart('+', '-'))) {
                            $fails.Add("${f}:${ln} binds $key to $w -- not an alias in this build and not a known game command")
                        }
                    }
                }
            }
        }
    }

    #  exec of a file the build does not ship --------------------------------
    foreach ($f in $skeys) {
        if (-not $f.EndsWith(".cfg", [StringComparison]::Ordinal)) { continue }
        foreach ($cl in (Code-Lines $files[$f])) {
            $ln = $cl[0]; $l = $cl[1]
            foreach ($seg in [regex]::Split($l, '[;"]')) {
                $words = Split-Words $seg
                if ($words.Count -ge 2 -and $words[0] -ceq "exec" -and
                        $words[1].StartsWith("core/", [StringComparison]::Ordinal)) {
                    if (-not $files.ContainsKey("cfg/" + $words[1] + ".cfg")) {
                        $fails.Add("${f}:${ln} execs " + $words[1] + ", which this build does not contain")
                    }
                }
            }
        }
    }

    #  ASCII, quote balance, help line length --------------------------------
    foreach ($f in $skeys) {
        if (-not $f.EndsWith(".cfg", [StringComparison]::Ordinal)) { continue }
        $i = 0
        foreach ($l in (Split-Lines $files[$f])) {
            $i++
            $code = $l
            $cidx = $code.IndexOf('//')
            if ($cidx -ge 0) { $code = $code.Substring(0, $cidx) }
            $qcount = $code.Length - $code.Replace('"', '').Length
            if ($qcount % 2 -ne 0) { $fails.Add("${f}:${i} has an unbalanced quote") }
            foreach ($ch in $l.ToCharArray()) {
                if ([int]$ch -gt 127) { $fails.Add("${f}:${i} has a non-ASCII byte"); break }
            }
            if ($f -ceq "cfg/core/help.cfg" -and
                    $l.StartsWith('echo "', [StringComparison]::Ordinal) -and $l.Length -gt 78) {
                $fails.Add("${f}:${i} help echo line over 78 chars -- wraps badly in game")
            }
        }
    }

    #  movement excluded -> the raw WASD fallback MUST be bound --------------
    if ($modules -notcontains "movement") {
        $targets = @{}
        foreach ($cl in (Code-Lines $files["cfg/core/keys.cfg"])) {
            $m = [regex]::Match($cl[1], $scopeRe)
            if ($m.Success) { $targets[$m.Groups[2].Value] = $true }
        }
        foreach ($w in $WASD) {
            $raw = $w[2]
            if (-not $targets.ContainsKey($raw)) {
                $fails.Add("cfg/core/keys.cfg:0 movement is excluded but nothing is bound to $raw -- the friend cannot move")
            }
        }
    }
    return ,$fails
}

#  ---------------------------------------------------------------------------
#  Generation
#  ---------------------------------------------------------------------------

function Generate($profile) {
    #  Hashtable: files/rows/modules/files_modules/groups -- nothing touches disk
    #  until this has returned and validated clean.
    $wantM = @{}
    if ($null -ne $profile["modules"]) {
        foreach ($m in @($profile["modules"])) { $wantM[[string]$m] = $true }
    }
    #  Profiles written before the hud/radar split named the whole hud module.
    #  Its user-visible half was the radar boost; the colour half now rides
    #  with movement, so the old name maps straight onto 'radar'.
    if ($wantM.ContainsKey("hud")) { $wantM.Remove("hud"); $wantM["radar"] = $true }
    $unknown = @()
    foreach ($m in (Hash-Keys $wantM)) { if ($MODULE_ORDER -notcontains $m) { $unknown += $m } }
    if ($unknown.Count -gt 0) { throw ("unknown module(s): " + ($unknown -join ", ")) }
    $modules = @($MODULE_ORDER | Where-Object { $wantM.ContainsKey($_) })
    $wantG = @{}
    if ($null -ne $profile["groups"]) {
        foreach ($g in @($profile["groups"])) { $wantG[[string]$g] = $true }
    }
    $unknown = @()
    foreach ($g in (Hash-Keys $wantG)) {
        $known = $false
        foreach ($gg in $script:GROUPS) { if ($gg[0] -ceq $g) { $known = $true; break } }
        if (-not $known) { $unknown += $g }
    }
    if ($unknown.Count -gt 0) { throw ("unknown settings group(s): " + ($unknown -join ", ")) }
    $groups = @($script:GROUPS | Where-Object { $wantG.ContainsKey($_[0]) } | ForEach-Object { $_[0] })
    $keymap = $profile["keys"]
    if ($null -eq $keymap) { $keymap = @{} }
    foreach ($tgt in (Hash-Keys $keymap)) {
        $k = [string]$keymap[$tgt]
        if (-not $BINDS_BY_TARGET.ContainsKey($tgt)) {
            throw "profile remaps '$tgt', which keys.cfg does not bind"
        }
        if ($k -cne "-" -and -not [regex]::IsMatch($k, $KEYS_RE)) {
            throw "profile maps $tgt to '$k', not a key name CS2 knows"
        }
        if ($k -ceq "-" -and $WASD_VERBS.ContainsKey($tgt)) {
            throw "WASD binds cannot be dropped (the friend could not move) -- remap them instead"
        }
        if ($k -ceq "-" -and $tgt -ceq "exec core/help") {
            throw "the F11 help bind stays in every build"
        }
    }

    $files = @{}
    if ($profile.ContainsKey('use_autoexec') -and -not [bool]$profile['use_autoexec']) { }
    else { $files["cfg/autoexec.cfg"] = Build-Autoexec $groups }
    #  Features the user picked -> the .cfg files that ship, plus the binds
    #  whose file ships for the OTHER half of hud.cfg and so must be dropped
    #  by name instead of by module.
    $fileMods = Module-Files $modules
    $radar = ($modules -contains "radar")
    $drop = @{}
    if (-not $radar)                        { $drop["+slx_radar_boost"] = $true }
    if ($modules -notcontains "movement")   { $drop["hud_fb_toggle"] = $true }

    $kr = Build-Keys $fileMods $keymap $drop
    $files["cfg/core/keys.cfg"] = $kr[0]
    $rows = $kr[1]
    $files["cfg/core/reg.cfg"] = Build-Reg $fileMods
    $files["cfg/core/load.cfg"] = Build-Load $fileMods
    $files["cfg/core/diag.cfg"] = Build-Diag $fileMods
    $default = ($modules.Count -eq $MODULE_ORDER.Count -and $keymap.Count -eq 0 -and $drop.Count -eq 0)
    if ($default) { $files["cfg/core/help.cfg"] = Read-Master "core\help.cfg" }
    else          { $files["cfg/core/help.cfg"] = Build-Help $rows $fileMods }
    foreach ($m in $fileMods) {
        $t = Read-Master "core\modules\$m.cfg"
        if ($m -ceq 'hud') { $t = Build-Hud $t $profile['hud_colors'] $radar }
        if ($m -ceq "movement") { $t = Build-Movement $t $keymap }
        $files["cfg/core/modules/$m.cfg"] = $t
    }
    return @{ files = $files; rows = $rows; modules = $modules; files_modules = $fileMods; groups = $groups }
}

#  ---------------------------------------------------------------------------
#  INSTALL.txt
#  ---------------------------------------------------------------------------

function Build-Install($profile, $rows, $modules, $groups) {
    $keyFor = {
        param([string]$orig)
        foreach ($row in $rows) { if ($row[1] -ceq $orig) { return $row[0] } }
        return $null
    }
    $excluded = @($MODULE_ORDER | Where-Object { $modules -notcontains $_ })
    $goff = @($script:GROUPS | Where-Object { $groups -notcontains $_[0] } | ForEach-Object { $_[0] })
    $incl = "(none)"; if ($modules.Count -gt 0)  { $incl = $modules -join ", " }
    $excl = "(none)"; if ($excluded.Count -gt 0) { $excl = $excluded -join ", " }
    $L = New-Object 'System.Collections.Generic.List[string]'
    $L.Add("CS2 AUTOEXEC + NULLBINDS -- custom build for " + $profile["friend"])
    $L.Add("=" * 72)
    $L.Add("")
    $L.Add("Built by _tools_customize.py from the AUTOEXEC+NULLBINDS v1 master.")
    $L.Add("")
    $L.Add("Included modules : " + $incl)
    $L.Add("Excluded modules : " + $excl)
    if ($goff.Count -gt 0) { $L.Add("Settings left out: " + ($goff -join ", ")) }
    $L.Add("")
    $L.Add("INSTALL")
    $L.Add("-------")
    $L.Add("1. Copy the contents of THIS folder into the game's csgo folder,")
    $L.Add("   merging:")
    $L.Add('     <Steam>\steamapps\common\Counter-Strike Global Offensive\game\csgo\')
    $L.Add('   (cfg\ lands on cfg\ -- this only adds files.)')
    if ($profile.ContainsKey('use_autoexec') -and -not [bool]$profile['use_autoexec']) {
        $L.Add('2. Keep your existing autoexec.cfg. Copy only the cfg\core folder, then run:')
        $L.Add('   exec core/load')
    } else {
        $L.Add("2. Nothing else. No restart, no launch options: CS2 runs")
        $L.Add('   cfg\autoexec.cfg on its own, and its last line is exec core/load.')
    }
    $L.Add("")
    $L.Add("CONSOLE SHOULD PRINT")
    $L.Add("--------------------")
    $L.Add("  [AUTOEXEC] INITIALIZING CONFIGURATION... [AUTOEXEC]")
    $L.Add("  [CORE] reg + " + $modules.Count + " modules loaded")
    $L.Add("  [AUTOEXEC] CONFIGURATION LOADED SUCCESSFULLY! [AUTOEXEC]")
    $L.Add("")
    $L.Add('If the middle line is missing, core\ did not load -- no key is bound')
    $L.Add("at all and you cannot move. Recovery, typed into the console:")
    $L.Add("")
    $L.Add("  bind " + (& $keyFor "+slx_forward") + " +forward; bind " +
           (& $keyFor "+slx_left") + " +left; bind " +
           (& $keyFor "+slx_back") + " +back; bind " +
           (& $keyFor "+slx_right") + " +right")
    $L.Add("")
    if ($modules -contains "movement") {
        $L.Add("PANIC KEY")
        $L.Add("---------")
        $L.Add((& $keyFor "mv_reset") + " -- unsticks movement and a held use (alt-tab, console, round")
        $L.Add("restart). Mash it: one press clears one thing, six cover all.")
        $L.Add((& $keyFor "mv_toggle") + " -- hands W/A/S/D straight back to stock CS2 (again to re-arm).")
        $L.Add("")
    }
    $L.Add((& $keyFor "exec core/help") + " prints the key map in game.  exec core/diag  names the layer that")
    $L.Add("failed to load, if anything above is missing.")
    $L.Add("")
    return [string]::Join("`n", $L)
}

#  ---------------------------------------------------------------------------
#  profile.json -- same bytes json.dumps(indent=2, sort_keys=True) produces
#  ---------------------------------------------------------------------------

function ConvertTo-PyJsonString([string]$s) {
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    foreach ($ch in $s.ToCharArray()) {
        $c = [int]$ch
        if ($ch -eq '"')         { [void]$sb.Append('\"') }
        elseif ($ch -eq '\')     { [void]$sb.Append('\\') }
        elseif ($c -eq 8)        { [void]$sb.Append('\b') }
        elseif ($c -eq 9)        { [void]$sb.Append('\t') }
        elseif ($c -eq 10)       { [void]$sb.Append('\n') }
        elseif ($c -eq 12)       { [void]$sb.Append('\f') }
        elseif ($c -eq 13)       { [void]$sb.Append('\r') }
        elseif ($c -lt 32 -or $c -gt 126) { [void]$sb.Append('\u{0:x4}' -f $c) }
        else                     { [void]$sb.Append($ch) }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-PyJson($obj, [int]$depth) {
    if ($null -eq $obj) { return "null" }
    if ($obj -is [bool]) { if ($obj) { return "true" } else { return "false" } }
    if ($obj -is [string]) { return ConvertTo-PyJsonString $obj }
    if ($obj -is [System.Collections.IDictionary]) {
        $keys = [string[]](@(Hash-Keys $obj))
        [Array]::Sort($keys, [System.StringComparer]::Ordinal)
        if ($keys.Count -eq 0) { return "{}" }
        $ind2 = "  " * ($depth + 1)
        $items = @()
        foreach ($k in $keys) {
            $items += $ind2 + (ConvertTo-PyJsonString $k) + ": " + (ConvertTo-PyJson $obj[$k] ($depth + 1))
        }
        return "{`n" + ($items -join ",`n") + "`n" + ("  " * $depth) + "}"
    }
    if ($obj -is [System.Collections.IEnumerable]) {
        $items = @($obj)
        if ($items.Count -eq 0) { return "[]" }
        $ind2 = "  " * ($depth + 1)
        $parts = @()
        foreach ($it in $items) { $parts += $ind2 + (ConvertTo-PyJson $it ($depth + 1)) }
        return "[`n" + ($parts -join ",`n") + "`n" + ("  " * $depth) + "]"
    }
    return [string]$obj
}

function Read-Profile([string]$path) {
    $json = [System.IO.File]::ReadAllText($path, $UTF8_NB)
    $obj = $json | ConvertFrom-Json
    $profile = @{}
    foreach ($prop in $obj.PSObject.Properties) {
        if ($prop.Name -ceq "keys") {
            $km = @{}
            if ($null -ne $prop.Value) {
                foreach ($kp in $prop.Value.PSObject.Properties) {
                    $km[$kp.Name] = [string]$kp.Value
                }
            }
            $profile["keys"] = $km
        } elseif ($prop.Name -ceq "modules" -or $prop.Name -ceq "groups") {
            $profile[$prop.Name] = @($prop.Value | ForEach-Object { [string]$_ })
        } elseif ($prop.Name -ceq "hud_colors") {
            $hc = @{}
            if ($null -ne $prop.Value) { foreach ($hp in $prop.Value.PSObject.Properties) { $hc[$hp.Name] = [string]$hp.Value } }
            $profile[$prop.Name] = $hc
        } else {
            $profile[$prop.Name] = $prop.Value
        }
    }
    return $profile
}

#  ---------------------------------------------------------------------------
#  The interactive UI -- a keyboard-driven TUI. Arrow keys move a cursor,
#  Space toggles checkboxes, Enter confirms, and Esc anywhere asks before
#  quitting (except mid text-entry, where Esc cancels the entry). Only used
#  when no --profile is given; scripted runs keep the plain output path in
#  Invoke-Build. ASCII only: PS 5.1 mangles Unicode in BOM-less scripts.
#
#  Rendering: each screen Clear-Host's once, then every keypress repaints
#  the whole frame in place from (0,0). A frame is built as one list of
#  padded lines and written in as few [Console]::Write calls as possible
#  (consecutive same-colour lines are grouped), so the redraw does not
#  flicker and stale characters never survive. Every block is centered as
#  a unit -- the padding comes from the block's LONGEST line, cursor
#  column included, re-measured against the current console width on every
#  frame; below ~70 columns the layout degrades to left-aligned.
#
#  Testability: every keypress comes from $script:ReadKey, every line of
#  text from $script:ReadLine, and the console size from $script:ReadWidth
#  / $script:ReadHeight, so tests can dot-source this file with
#  SLX_NO_MAIN=1, replace the scriptblocks with a queue of synthetic
#  ConsoleKeyInfo objects, and drive the whole flow. Each screen is a
#  state machine: Update-* takes (state, key) and mutates state, Render-*
#  turns state into a frame. Every rendered frame is also appended (plain
#  text) to $script:FrameLog. With piped stdin -- or SLX_UI=line -- one
#  input line maps to one keypress: ""=Enter, " "=Space, up/down/left/
#  right, pgup/pgdn, esc, del, f10, back; anything else = its first char.
#  ---------------------------------------------------------------------------

$script:UI = $false

$script:ReadLine = { [Console]::In.ReadLine() }
$script:ReadKey  = {
    $lineMode = ($env:SLX_UI -eq 'line')
    if (-not $lineMode) {
        try { $lineMode = [Console]::IsInputRedirected } catch { $lineMode = $false }
    }
    if ($lineMode) {
        $l = & $script:ReadLine
        if ($null -eq $l) { return $null }    #  EOF: the caller aborts cleanly
        return (Key-FromLine $l)
    }
    return [Console]::ReadKey($true)
}
$script:ReadWidth = {
    try { $w = $Host.UI.RawUI.WindowSize.Width;  if ($w -gt 0) { return $w } } catch { }
    return 80
}
$script:ReadHeight = {
    try { $h = $Host.UI.RawUI.WindowSize.Height; if ($h -gt 0) { return $h } } catch { }
    return 25
}
$script:FrameLog = New-Object 'System.Collections.Generic.List[string]'

#  Short professional descriptions for the feature checklist. The
#  manifest's own descriptions stay untouched; these are display-only.
$UI_MODULE_DESC = @{
    "movement"  = "null-binds - snap-tap WASD, with the mode HUD colour"
    "crosshair" = "seven presets, outline and colour toggles"
    "weapons"   = "fast bomb/gun drop and quickswitch"
    "viewmodel" = "eight positions on one cycle key"
    "radar"     = "radar boost - wider radar while a key is held"
}

#  ---------------------------------------------------------------------------
#  Console + frame primitives
#  ---------------------------------------------------------------------------

function New-KeyInfo([string]$c, $k) {
    $ch = [char]0
    if ($c.Length -gt 0) { $ch = $c[0] }
    return New-Object System.ConsoleKeyInfo($ch, [ConsoleKey]$k, $false, $false, $false)
}

function Key-FromLine([string]$line) {
    #  Line mode: one line of stdin is one keypress (see the header above).
    if ($line -eq "")  { return (New-KeyInfo "`r" ([ConsoleKey]::Enter)) }
    if ($line -eq " ") { return (New-KeyInfo " "  ([ConsoleKey]::Spacebar)) }
    $named = @{
        "up"   = [ConsoleKey]::UpArrow;    "down"  = [ConsoleKey]::DownArrow
        "left" = [ConsoleKey]::LeftArrow;  "right" = [ConsoleKey]::RightArrow
        "pgup" = [ConsoleKey]::PageUp;     "pgdn"  = [ConsoleKey]::PageDown
        "esc"  = [ConsoleKey]::Escape;     "del"   = [ConsoleKey]::Delete
        "f10"  = [ConsoleKey]::F10;        "tab"   = [ConsoleKey]::Tab
        "back" = [ConsoleKey]::Backspace
    }
    $low = $line.ToLowerInvariant()
    if ($named.ContainsKey($low)) { return (New-KeyInfo "" $named[$low]) }
    $k = [ConsoleKey]::NoName
    $up = ([string]$line[0]).ToUpperInvariant()
    if ($up -match '^[A-Z]$')  { $k = [Enum]::Parse([ConsoleKey], $up) }
    if ($up -match '^[0-9]$')  { $k = [Enum]::Parse([ConsoleKey], "D" + $up) }
    return (New-KeyInfo ([string]$line[0]) $k)
}

function Test-RealConsole {
    try { return -not [Console]::IsOutputRedirected } catch { return $false }
}

function Get-ConWidth  { return [int](& $script:ReadWidth) }
function Get-ConHeight { return [int](& $script:ReadHeight) }

function New-Frame {
    #  The comma matters: an empty List unrolls to $null in the pipeline.
    return ,(New-Object 'System.Collections.Generic.List[object]')
}

function Get-BlockPad([string[]]$lines) {
    #  Center a block as a unit: the padding comes from its LONGEST line,
    #  so columns inside the block stay aligned. Below ~70 columns the
    #  layout degrades to left-aligned.
    $w = Get-ConWidth
    $max = 0
    foreach ($l in $lines) { if ($l.Length -gt $max) { $max = $l.Length } }
    if ($w -ge 70 -and $max -lt $w) { return [int](($w - $max) / 2) }
    return 0
}

function Add-Lines($frame, [string[]]$lines, $colors) {
    #  Append a centered block to the frame. $colors is one colour for the
    #  whole block, or one per line.
    $pad = Get-BlockPad $lines
    $isArr = ($colors -is [array])
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $c = $colors
        if ($isArr) { $c = $colors[$i] }
        $frame.Add(@{ T = (" " * $pad) + $lines[$i]; C = [string]$c })
    }
}

function Add-Gap($frame, [int]$n) {
    for ($i = 0; $i -lt $n; $i++) { $frame.Add(@{ T = ""; C = "Gray" }) }
}

function Write-Frame($frame, $cursor) {
    #  One full repaint: every line is padded to the console width so stale
    #  characters never survive, and consecutive same-colour lines go out
    #  in a single Write call to keep the redraw flicker-free. $cursor, when
    #  set, is @{X;Y} for text entry (the cursor is hidden otherwise).
    $w = Get-ConWidth
    [void]$script:FrameLog.Add("<<FRAME>>")
    foreach ($l in $frame) { [void]$script:FrameLog.Add($l.T.TrimEnd()) }
    if (-not (Test-RealConsole)) {
        foreach ($l in $frame) {
            try { [Console]::WriteLine($l.T.TrimEnd()) } catch { }
        }
        return
    }
    $h = Get-ConHeight
    $lines = New-Object 'System.Collections.Generic.List[object]'
    foreach ($l in $frame) {
        $t = $l.T
        if ($t.Length -ge $w) { $t = $t.Substring(0, $w - 1) }
        else { $t = $t.PadRight($w - 1) }
        $lines.Add(@{ T = $t; C = $l.C })
    }
    while ($lines.Count -lt $h) { $lines.Add(@{ T = (" " * ($w - 1)); C = "Gray" }) }
    try { [Console]::SetCursorPosition(0, 0) } catch { }
    try { [Console]::CursorVisible = $false } catch { }
    $i = 0
    while ($i -lt $lines.Count) {
        $j = $i
        while ($j + 1 -lt $lines.Count -and $lines[$j + 1].C -eq $lines[$i].C) { $j++ }
        $sb = New-Object System.Text.StringBuilder
        for ($k = $i; $k -le $j; $k++) {
            [void]$sb.Append($lines[$k].T)
            if ($k -lt $lines.Count - 1) { [void]$sb.Append("`n") }
        }
        $old = [Console]::ForegroundColor
        try {
            [Console]::ForegroundColor = [ConsoleColor]($lines[$i].C)
            [Console]::Write($sb.ToString())
        } catch { }
        finally { try { [Console]::ForegroundColor = $old } catch { } }
        $i = $j + 1
    }
    if ($null -ne $cursor) {
        try {
            $cx = [Math]::Min([Math]::Max($cursor.X, 0), $w - 2)
            $cy = [Math]::Min([Math]::Max($cursor.Y, 0), $h - 1)
            [Console]::SetCursorPosition($cx, $cy)
            [Console]::CursorVisible = $true
        } catch { }
    }
}

function New-Screen {
    #  Called once per screen; frames then repaint in place from (0,0).
    if (Test-RealConsole) {
        try { Clear-Host } catch { }
        try { [Console]::SetCursorPosition(0, 0) } catch { }
    }
}

function Get-StepLine([int]$step) {
    return ("STEP " + $step + " OF 5   [" + ("#" * $step) + ("-" * (5 - $step)) + "]")
}

function Add-Header($frame, [int]$step, [string]$title) {
    Add-Gap $frame 1
    Add-Lines $frame @((Get-StepLine $step)) "DarkCyan"
    Add-Gap $frame 1
    Add-Lines $frame @($title) "Cyan"
    Add-Gap $frame 1
}

#  ---------------------------------------------------------------------------
#  Screen driver: render, read a key, update state -- until done or quit
#  ---------------------------------------------------------------------------

function Invoke-Screen($state, [scriptblock]$update, [scriptblock]$render) {
    New-Screen
    while ($true) {
        $r = & $render $state
        Write-Frame $r.Frame $r.Cursor
        if ($state.Done) { return "done" }
        if ($state.Quit) {
            if (Confirm-Quit) { return "quit" }
            $state.Quit = $false
            New-Screen
            continue
        }
        $k = & $script:ReadKey
        if ($null -eq $k) { return "eof" }
        & $update $state $k
    }
}

function Confirm-Quit {
    #  Esc anywhere lands here; consistent on every screen.
    New-Screen
    $f = New-Frame
    Add-Gap $f 3
    Add-Lines $f @(
        "+------------------------------------------------------+",
        "|      Quit setup?  Nothing has been written yet.      |",
        "+------------------------------------------------------+"
    ) "Yellow"
    Add-Gap $f 1
    Add-Lines $f @("y: quit        n: stay") "Gray"
    Write-Frame $f $null
    while ($true) {
        $k = & $script:ReadKey
        if ($null -eq $k) { return $true }
        $c = [char]::ToLowerInvariant($k.KeyChar)
        if ($c -eq 'y') { return $true }
        if ($c -eq 'n' -or $k.Key -eq [ConsoleKey]::Escape) { return $false }
    }
}

#  ---------------------------------------------------------------------------
#  Welcome
#  ---------------------------------------------------------------------------

function Update-Welcome($state, $key) {
    if ($key.Key -eq [ConsoleKey]::Escape) { $state.Quit = $true }
    else { $state.Done = $true }
}

function Render-Welcome($state) {
    $f = New-Frame
    Add-Gap $f 2
    Add-Lines $f @(
        "+==============================================================+",
        "|                                                              |",
        "|                       CS2  CONFIG  SETUP                     |",
        "|                  AUTOEXEC  +  NULLBINDS  v1                  |",
        "|                                                              |",
        "+==============================================================+"
    ) "Cyan"
    Add-Gap $f 1
    Add-Lines $f @("sLix1337  --  config build tool") "DarkCyan"
    Add-Gap $f 2
    Add-Lines $f @(
        "Builds a tailored copy of this CS2 config: choose the features",
        "and settings to include, adjust the key bindings, and write a",
        "validated, ready-to-copy folder under builds\."
    ) "White"
    Add-Gap $f 2
    Add-Lines $f @("Press any key to begin        Esc: quit") "Gray"
    return @{ Frame = $f; Cursor = $null }
}

#  ---------------------------------------------------------------------------
#  Text entry (build name; also the model for key-name entry)
#  ---------------------------------------------------------------------------

function New-TextState([int]$step, [string]$title, [string]$blurb, [string]$prompt,
                       [string]$initial, [string]$hint) {
    return @{ Step = $step; Title = $title; Blurb = $blurb; Prompt = $prompt
              Buf = $initial; Hint = $hint; Done = $false; Quit = $false }
}

function Update-TextEntry($state, $key) {
    if ($key.Key -eq [ConsoleKey]::Enter)     { $state.Done = $true; return }
    if ($key.Key -eq [ConsoleKey]::Escape)    { $state.Quit = $true; return }
    if ($key.Key -eq [ConsoleKey]::Backspace) {
        if ($state.Buf.Length -gt 0) { $state.Buf = $state.Buf.Substring(0, $state.Buf.Length - 1) }
        return
    }
    $c = [int]$key.KeyChar
    if ($c -ge 32 -and $c -lt 127 -and $state.Buf.Length -lt 40) {
        $state.Buf += $key.KeyChar
    }
}

function Render-TextEntry($state) {
    $f = New-Frame
    Add-Header $f $state.Step $state.Title
    if ($state.Blurb -ne "") { Add-Lines $f @($state.Blurb) "White"; Add-Gap $f 1 }
    $line = $state.Prompt + $state.Buf
    $pad = Get-BlockPad @($line)
    Add-Lines $f @($line) "White"
    $y = $f.Count - 1
    Add-Gap $f 1
    if ($state.Hint -ne "") { Add-Lines $f @($state.Hint) "Gray" }
    return @{ Frame = $f; Cursor = @{ X = $pad + $line.Length; Y = $y } }
}

#  ---------------------------------------------------------------------------
#  Checklist (features, settings groups)
#  ---------------------------------------------------------------------------

function New-ChecklistState([int]$step, [string]$title, $items, [string]$hint) {
    $on = @{}
    foreach ($it in $items) { $on[$it[0]] = $true }
    return @{ Step = $step; Title = $title; Items = $items; Hint = $hint
              On = $on; Pos = 0; Done = $false; Quit = $false }
}

function Update-Checklist($state, $key) {
    if ($key.Key -eq [ConsoleKey]::UpArrow) {
        if ($state.Pos -gt 0) { $state.Pos-- }
    } elseif ($key.Key -eq [ConsoleKey]::DownArrow) {
        if ($state.Pos -lt $state.Items.Count - 1) { $state.Pos++ }
    } elseif ($key.Key -eq [ConsoleKey]::Spacebar) {
        $id = $state.Items[$state.Pos][0]
        $state.On[$id] = -not $state.On[$id]
    } elseif ($key.Key -eq [ConsoleKey]::Enter) {
        $state.Done = $true
    } elseif ($key.Key -eq [ConsoleKey]::Escape) {
        $state.Quit = $true
    }
}

function Render-Checklist($state) {
    $f = New-Frame
    Add-Header $f $state.Step $state.Title
    $rows = New-Object 'System.Collections.Generic.List[string]'
    $cols = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; $i -lt $state.Items.Count; $i++) {
        $id = $state.Items[$i][0]
        $mark = "[ ]"
        if ($state.On[$id]) { $mark = "[x]" }
        $cur = "  "; $col = "White"
        if ($i -eq $state.Pos) { $cur = "> "; $col = "Cyan" }
        $rows.Add($cur + $mark + "  " + $id.PadRight(11) + $state.Items[$i][1])
        $cols.Add($col)
    }
    Add-Lines $f $rows.ToArray() $cols.ToArray()
    Add-Gap $f 1
    if ($state.Hint -ne "") { Add-Lines $f @($state.Hint) "Gray" }
    Add-Lines $f @("Up/Down: move      Space: toggle      Enter: confirm      Esc: quit") "Gray"
    return @{ Frame = $f; Cursor = $null }
}

#  ---------------------------------------------------------------------------
#  Option menu (keys gate, review)
#  ---------------------------------------------------------------------------

function New-MenuState([int]$step, [string]$title, [string[]]$options, [string[]]$blurb) {
    return @{ Step = $step; Title = $title; Options = $options; Blurb = $blurb
              Pos = 0; Choice = -1; Done = $false; Quit = $false }
}

function Update-Menu($state, $key) {
    $k = $key.Key
    if ($k -eq [ConsoleKey]::UpArrow -or $k -eq [ConsoleKey]::LeftArrow) {
        if ($state.Pos -gt 0) { $state.Pos-- }
    } elseif ($k -eq [ConsoleKey]::DownArrow -or $k -eq [ConsoleKey]::RightArrow) {
        if ($state.Pos -lt $state.Options.Count - 1) { $state.Pos++ }
    } elseif ($k -eq [ConsoleKey]::Enter) {
        $state.Choice = $state.Pos; $state.Done = $true
    } elseif ($k -eq [ConsoleKey]::Escape) {
        $state.Quit = $true
    }
}

function Render-Menu($state) {
    $f = New-Frame
    Add-Header $f $state.Step $state.Title
    if ($null -ne $state.Blurb -and $state.Blurb.Count -gt 0) {
        Add-Lines $f $state.Blurb "White"
        Add-Gap $f 1
    }
    $rows = New-Object 'System.Collections.Generic.List[string]'
    $cols = New-Object 'System.Collections.Generic.List[string]'
    for ($i = 0; $i -lt $state.Options.Count; $i++) {
        $cur = "  "; $col = "White"
        if ($i -eq $state.Pos) { $cur = "> "; $col = "Cyan" }
        $rows.Add($cur + $state.Options[$i])
        $cols.Add($col)
    }
    Add-Lines $f $rows.ToArray() $cols.ToArray()
    Add-Gap $f 1
    Add-Lines $f @("Up/Down: move      Enter: select      Esc: quit") "Gray"
    return @{ Frame = $f; Cursor = $null }
}

#  ---------------------------------------------------------------------------
#  Key bindings: scrollable list + inline key-name entry
#  ---------------------------------------------------------------------------

function New-KeysState($modules) {
    $kr = Build-Keys $modules @{}
    return @{ Rows = $kr[1]; Map = @{}; Pos = 0; Scroll = 0
              Editing = $false; EBuf = ""; EErr = ""; Err = ""
              Done = $false; Quit = $false }
}

function Get-RowKey($state, [int]$i) {
    $orig = $state.Rows[$i][1]
    if ($state.Map.ContainsKey($orig)) {
        $v = $state.Map[$orig]
        if ($v -ceq "-") { return "--" }
        return $v
    }
    return $state.Rows[$i][0]
}

function Test-KeyName($state, [string]$v) {
    #  $null = acceptable; otherwise the inline error to show, live.
    if ($v -eq "") { return $null }
    if (-not [regex]::IsMatch($v, $KEYS_RE)) {
        return ("'" + $v + "' is not a key name CS2 knows")
    }
    $vl = $v.ToLowerInvariant()
    for ($i = 0; $i -lt $state.Rows.Count; $i++) {
        if ($i -eq $state.Pos) { continue }
        if ((Get-RowKey $state $i).ToLowerInvariant() -eq $vl) {
            return ($v + " is already bound to '" + $state.Rows[$i][3][3] + "'")
        }
    }
    return $null
}

function Update-KeysList($state, $key) {
    $state.Err = ""
    if ($state.Editing) {
        if ($key.Key -eq [ConsoleKey]::Escape) {
            $state.Editing = $false; $state.EBuf = ""; $state.EErr = ""; return
        }
        if ($key.Key -eq [ConsoleKey]::Enter) {
            $v = $state.EBuf.Trim()
            if ($v -eq "") { $state.Editing = $false; $state.EErr = ""; return }
            $err = Test-KeyName $state $v
            if ($null -ne $err) { $state.EErr = $err; return }
            $orig = $state.Rows[$state.Pos][1]
            if ($v -ceq $state.Rows[$state.Pos][0]) { [void]$state.Map.Remove($orig) }
            else { $state.Map[$orig] = $v }
            $state.Editing = $false; $state.EBuf = ""; $state.EErr = ""
            return
        }
        if ($key.Key -eq [ConsoleKey]::Backspace) {
            if ($state.EBuf.Length -gt 0) { $state.EBuf = $state.EBuf.Substring(0, $state.EBuf.Length - 1) }
        } else {
            $c = [int]$key.KeyChar
            if ($c -ge 32 -and $c -lt 127 -and $state.EBuf.Length -lt 30) {
                $state.EBuf += $key.KeyChar
            }
        }
        $err = Test-KeyName $state $state.EBuf.Trim()
        if ($null -eq $err) { $err = "" }
        $state.EErr = $err
        return
    }
    $k = $key.Key
    if ($k -eq [ConsoleKey]::UpArrow) {
        if ($state.Pos -gt 0) { $state.Pos-- }
    } elseif ($k -eq [ConsoleKey]::DownArrow) {
        if ($state.Pos -lt $state.Rows.Count) { $state.Pos++ }
    } elseif ($k -eq [ConsoleKey]::PageUp) {
        $state.Pos -= 10; if ($state.Pos -lt 0) { $state.Pos = 0 }
    } elseif ($k -eq [ConsoleKey]::PageDown) {
        $state.Pos += 10; if ($state.Pos -gt $state.Rows.Count) { $state.Pos = $state.Rows.Count }
    } elseif ($k -eq [ConsoleKey]::F10) {
        $state.Done = $true
    } elseif ($k -eq [ConsoleKey]::Enter) {
        if ($state.Pos -eq $state.Rows.Count) { $state.Done = $true }
        else { $state.Editing = $true; $state.EBuf = ""; $state.EErr = "" }
    } elseif ($k -eq [ConsoleKey]::Delete -or $key.KeyChar -eq '-') {
        if ($state.Pos -lt $state.Rows.Count) {
            $orig = $state.Rows[$state.Pos][1]
            if ($WASD_VERBS.ContainsKey($orig)) {
                $state.Err = "movement binds cannot be removed - remap them instead"
            } elseif ($orig -ceq "exec core/help") {
                $state.Err = "the help bind stays in every build"
            } elseif ($state.Map.ContainsKey($orig) -and $state.Map[$orig] -ceq "-") {
                [void]$state.Map.Remove($orig)     #  pressed twice: restore
            } else {
                $state.Map[$orig] = "-"
            }
        }
    } elseif ($k -eq [ConsoleKey]::Escape) {
        $state.Quit = $true
    }
}

function Render-KeysList($state) {
    $f = New-Frame
    Add-Header $f 4 "Key bindings"
    $total = $state.Rows.Count + 1          #  + the Done row
    $chrome = 15
    if ($state.Editing) { $chrome = 18 }
    $vis = (Get-ConHeight) - $chrome
    if ($vis -lt 4) { $vis = 4 }
    if ($state.Pos -lt $state.Scroll) { $state.Scroll = $state.Pos }
    if ($state.Pos -ge $state.Scroll + $vis) { $state.Scroll = $state.Pos - $vis + 1 }
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $cols  = New-Object 'System.Collections.Generic.List[string]'
    if ($state.Scroll -gt 0) {
        $lines.Add("    ... " + $state.Scroll + " more above")
        $cols.Add("DarkGray")
    }
    $last = $state.Scroll + $vis - 1
    if ($last -ge $total) { $last = $total - 1 }
    for ($i = $state.Scroll; $i -le $last; $i++) {
        $cur = "  "; $col = "White"
        if ($i -eq $state.Pos) { $cur = "> "; $col = "Cyan" }
        if ($i -eq $state.Rows.Count) {
            $lines.Add($cur + "[ Done - go to review ]")
            $cols.Add($col)
            continue
        }
        $keyd = Get-RowKey $state $i
        if ($keyd -ceq "--" -and $i -ne $state.Pos) { $col = "DarkGray" }
        $lines.Add($cur + ([string]$state.Rows[$i][3][3]).PadRight(34, '.') + " " + $keyd)
        $cols.Add($col)
    }
    if ($last -lt $total - 1) {
        $lines.Add("    ... " + ($total - 1 - $last) + " more below")
        $cols.Add("DarkGray")
    }
    Add-Lines $f $lines.ToArray() $cols.ToArray()
    Add-Gap $f 1
    if ($state.Err -ne "") { Add-Lines $f @($state.Err) "Red" }
    Add-Lines $f @("Enter: remap      Del/-: remove bind      F10: finish      Esc: quit") "Gray"
    Add-Lines $f @("key names: F1..F12, KP_0..KP_9, KP_ENTER, MOUSE3..5, UPARROW, SPACE, scancodeNN, A..Z, 0..9") "Gray"
    $cursor = $null
    if ($state.Editing) {
        Add-Gap $f 1
        $line = "new key for '" + $state.Rows[$state.Pos][3][3] + "': " + $state.EBuf
        $pad = Get-BlockPad @($line)
        Add-Lines $f @($line) "White"
        $cursor = @{ X = $pad + $line.Length; Y = $f.Count - 1 }
        $msg = "Enter: accept      Esc: cancel"; $col = "Gray"
        if ($state.EErr -ne "") { $msg = $state.EErr; $col = "Red" }
        Add-Lines $f @($msg) $col
    }
    return @{ Frame = $f; Cursor = $cursor }
}

#  ---------------------------------------------------------------------------
#  The step flow: welcome -> name -> features -> settings -> keys -> review
#  ---------------------------------------------------------------------------

function Run-Interactive {
    try { $Host.UI.RawUI.WindowTitle = "CS2 Config Setup" } catch { }
    $name = "my-config"
    $step = 0
    while ($true) {
        if ($step -eq 0) {
            $st = @{ Done = $false; Quit = $false }
            $r = Invoke-Screen $st ${function:Update-Welcome} ${function:Render-Welcome}
            if ($r -ne "done") { return $null }
            $step = 1
        } elseif ($step -eq 1) {
            $st = New-TextState 1 "Build name" `
                "The build is written to builds\<name> next to this script." `
                "name: " $name "Enter: accept      empty = my-config      Esc: quit"
            $r = Invoke-Screen $st ${function:Update-TextEntry} ${function:Render-TextEntry}
            if ($r -ne "done") { return $null }
            $name = $st.Buf.Trim()
            if ($name -eq "") { $name = "my-config" }
            $name = Safe-DirName $name
            $step = 2
        } elseif ($step -eq 2) {
            $items = @($MODULES | ForEach-Object { ,@($_[0], $UI_MODULE_DESC[$_[0]]) })
            $st = New-ChecklistState 2 "Select the features to include" $items ""
            $r = Invoke-Screen $st ${function:Update-Checklist} ${function:Render-Checklist}
            if ($r -ne "done") { return $null }
            $modules = @($MODULE_ORDER | Where-Object { $st.On[$_] })
            $step = 3
        } elseif ($step -eq 3) {
            $st = New-ChecklistState 3 "Settings groups" $GROUPS `
                "Excluded groups keep the game defaults on the target machine."
            $r = Invoke-Screen $st ${function:Update-Checklist} ${function:Render-Checklist}
            if ($r -ne "done") { return $null }
            $groups = @($GROUPS | Where-Object { $st.On[$_[0]] } | ForEach-Object { $_[0] })
            $step = 4
        } elseif ($step -eq 4) {
            $gate = New-MenuState 4 "Key bindings" `
                @("Keep default keys", "Customize keys") `
                @("The default bindings are a complete, tested key map.")
            $r = Invoke-Screen $gate ${function:Update-Menu} ${function:Render-Menu}
            if ($r -ne "done") { return $null }
            $keymap = @{}
            if ($gate.Choice -eq 1) {
                $ks = New-KeysState $modules
                $r = Invoke-Screen $ks ${function:Update-KeysList} ${function:Render-KeysList}
                if ($r -ne "done") { return $null }
                $keymap = $ks.Map
            }
            $step = 5
        } else {
            $moved = 0; $removed = 0
            foreach ($kk in (Hash-Keys $keymap)) {
                if ($keymap[$kk] -ceq "-") { $removed++ } else { $moved++ }
            }
            $inclM = "(none)"; if ($modules.Count -gt 0) { $inclM = $modules -join ", " }
            $inclG = "(none)"; if ($groups.Count -gt 0)  { $inclG = $groups -join ", " }
            $outPath = [System.IO.Path]::GetFullPath((Join-Path $BUILDS (Safe-DirName $name)))
            $blurb = New-Object 'System.Collections.Generic.List[string]'
            $blurb.Add("build    : " + $name)
            $blurb.Add("features : " + $inclM)
            $blurb.Add("settings : " + $inclG)
            $blurb.Add("keys     : " + $moved + " remapped, " + $removed + " removed, rest on defaults")
            $blurb.Add("output   : " + $outPath)
            if ($modules -contains "movement" -and $modules -notcontains "hud") {
                $blurb.Add("note     : movement without hud - 4 empty stub aliases are generated")
            }
            $rv = New-MenuState 5 "Review" @("Build", "Start over", "Quit") $blurb.ToArray()
            $r = Invoke-Screen $rv ${function:Update-Menu} ${function:Render-Menu}
            if ($r -ne "done") { return $null }
            if ($rv.Choice -eq 0) {
                return @{ friend = $name; modules = $modules; groups = $groups; keys = $keymap }
            }
            if ($rv.Choice -eq 1) { $step = 1; continue }
            return $null
        }
    }
}

#  ---------------------------------------------------------------------------
#  Result screens
#  ---------------------------------------------------------------------------

function UI-Success([int]$fileCount, [string]$outPath, $modList, $rows) {
    New-Screen
    $f = New-Frame
    Add-Gap $f 2
    Add-Lines $f @(
        "+==============================================================+",
        "|                      BUILD  COMPLETE                         |",
        "+==============================================================+"
    ) "Green"
    Add-Gap $f 1
    $modstr = "(none)"; if ($modList.Count -gt 0) { $modstr = $modList -join ", " }
    Add-Lines $f @(
        ("wrote " + $fileCount + " files to:"),
        $outPath,
        ("modules: " + $modstr)
    ) "White"
    Add-Lines $f @("validation: clean - every alias, bind, exec and key checked") "Green"
    Add-Gap $f 1
    Add-Lines $f @(
        "TO INSTALL",
        "  1. Open the output folder above.",
        "  2. Copy its cfg folder into the game's csgo folder, merging:",
        "     <Steam>\steamapps\common\Counter-Strike Global Offensive\game\csgo\",
        "  3. Done - CS2 runs cfg\autoexec.cfg on its own."
    ) "White"
    Add-Gap $f 1
    Add-Lines $f @(("console should print:  [CORE] reg + " + $modList.Count + " modules loaded")) "Yellow"
    if ($modList -contains "movement") {
        $panic = $null
        foreach ($row in $rows) { if ($row[1] -ceq "mv_reset") { $panic = $row[0]; break } }
        if ($null -ne $panic) {
            Add-Lines $f @(("movement stuck in game? mash " + $panic.ToUpperInvariant() + " - the panic key")) "Yellow"
        }
    }
    Add-Gap $f 1
    Add-Lines $f @("INSTALL.txt in the build folder repeats these instructions.") "Gray"
    Add-Lines $f @("Press any key to exit") "Gray"
    Write-Frame $f $null
    [void](& $script:ReadKey)
}

function UI-Failure($fails) {
    New-Screen
    $f = New-Frame
    Add-Gap $f 2
    Add-Lines $f @(
        "+==============================================================+",
        "|          BUILD  FAILED - NOTHING WAS WRITTEN                 |",
        "+==============================================================+"
    ) "Red"
    Add-Gap $f 1
    foreach ($fail in $fails) { Add-Lines $f @("FAIL  " + $fail) "Red" }
    Add-Gap $f 1
    Add-Lines $f @("Fix the inputs and run the builder again.") "Gray"
    Add-Lines $f @("Press any key to exit") "Gray"
    Write-Frame $f $null
    [void](& $script:ReadKey)
}

#  ---------------------------------------------------------------------------
#  main
#  ---------------------------------------------------------------------------

function Safe-DirName([string]$name) {
    $o = [regex]::Replace($name, '[\\/:*?"<>|]', '-').Trim().Trim('.')
    if ($o -eq "") { return "unnamed" }
    return $o
}

function Invoke-Build($profile, $outName) {
    #  Shared by the interactive flow and --profile runs. Returns an exit
    #  code; prints plain output unless $script:UI is set.
    if ($null -eq $outName) {
        if ($null -eq $profile["friend"] -or [string]$profile["friend"] -eq "") {
            Write-Host "profile has no `"friend`" and no --out was given -- nothing to name the build"
            return 1
        }
        $out = Join-Path $BUILDS (Safe-DirName ([string]$profile["friend"]))
    } elseif (-not [System.IO.Path]::IsPathRooted($outName)) {
        $out = Join-Path $BUILDS $outName
    } else {
        $out = $outName
    }
    #  The writer below rmtree's out/cfg before writing, so a path that
    #  escapes builds/ (e.g. --out ../../evil) is a real hazard, not a
    #  cosmetic one. Normalise and refuse it.
    $bpFull  = [System.IO.Path]::GetFullPath($BUILDS).ToLowerInvariant()
    $outFull = [System.IO.Path]::GetFullPath($out).ToLowerInvariant()
    if (-not $outFull.StartsWith($bpFull + [System.IO.Path]::DirectorySeparatorChar)) {
        Write-Host ("output dir must stay inside " + $bpFull + " (got " + $outFull + ")")
        return 1
    }

    try {
        $gen = Generate $profile
    } catch {
        if ($script:UI) { UI-Failure @("build error: " + $_.Exception.Message) }
        else { Write-Host ("build error: " + $_.Exception.Message) }
        return 1
    }
    $files   = $gen["files"]
    $rows    = $gen["rows"]
    #  NOTE: distinct names, not $modules/$groups -- at script scope those
    #  would clobber the $MODULES/$GROUPS manifests (PowerShell variable
    #  names are case-insensitive).
    $modList  = $gen["modules"]
    $grpList  = $gen["groups"]

    $fails = Validate-Build $files $gen["files_modules"]
    if ($fails.Count -gt 0) {
        if ($script:UI) {
            UI-Failure $fails
        } else {
            Write-Host ""
            foreach ($f in $fails) { Write-Host ("  FAIL  " + $f) }
            Write-Host ""
            Write-Host ($fails.Count.ToString() + " problem(s) -- build NOT written.")
        }
        return 1
    }
    $profile["modules"] = $modList
    $profile["groups"]  = $grpList

    #  Clean slate for the directory this tool owns, so re-running with a
    #  smaller module set never leaves stale files behind.
    $cfgdir = Join-Path $out "cfg"
    if (Test-Path -LiteralPath $cfgdir -PathType Container) {
        Remove-Item -LiteralPath $cfgdir -Recurse -Force
    }
    $fkeys = [string[]](@(Hash-Keys $files))
    [Array]::Sort($fkeys, [System.StringComparer]::Ordinal)
    foreach ($rel in $fkeys) {
        $p = Join-Path $out ($rel -replace '/', '\')
        $d = Split-Path -Parent $p
        if (-not (Test-Path -LiteralPath $d)) { [void][System.IO.Directory]::CreateDirectory($d) }
        [System.IO.File]::WriteAllText($p, $files[$rel], $ASCII_ENC)
    }
    [void][System.IO.Directory]::CreateDirectory($out)
    #  The .py opens profile.json without newline="\n", so on Windows its
    #  \n becomes \r\n. Match that byte-for-byte so .py- and .ps1-written
    #  profiles diff clean against each other on Windows.
    [System.IO.File]::WriteAllText((Join-Path $out "profile.json"),
        ((ConvertTo-PyJson $profile 0) + "`n").Replace("`n", "`r`n"), $UTF8_NB)
    [System.IO.File]::WriteAllText((Join-Path $out "INSTALL.txt"),
        (Build-Install $profile $rows $modList $grpList), $ASCII_ENC)

    if ($script:UI) {
        UI-Success ($files.Count + 2) $outFull $modList $rows
    } else {
        Write-Host ""
        Write-Host ("  wrote " + ($files.Count + 2) + " files to " + $outFull)
        $modstr = "(none)"; if ($modList.Count -gt 0) { $modstr = $modList -join ", " }
        Write-Host ("  modules: " + $modstr)
        Write-Host "  validation: clean"
    }
    return 0
}

if ($env:SLX_NO_MAIN -ne '1') {
    $profilePath = $null
    $outName = $null
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i] -ceq "--profile" -and $i + 1 -lt $args.Count) { $profilePath = $args[$i + 1] }
        if ($args[$i] -ceq "--out" -and $i + 1 -lt $args.Count)     { $outName = $args[$i + 1] }
    }

    $profile = $null
    if ($null -ne $profilePath) {
        try {
            $profile = Read-Profile $profilePath
        } catch {
            Write-Host ("cannot read profile " + $profilePath + ": " + $_.Exception.Message)
            exit 1
        }
        Write-Host ("  profile: " + $profilePath)
    }
    if ($null -eq $profile) {
        #  Interactive: run the keyboard-driven TUI. --profile runs never
        #  touch this path, so scripts/tests keep plain output.
        $script:UI = $true
        $profile = Run-Interactive
        if ($null -eq $profile) {
            Write-Host "  setup cancelled -- nothing was written"
            exit 0
        }
    }

    exit (Invoke-Build $profile $outName)
}
