// ============================================================
// 미소녀 키우기 - 통합 프리셋 UI
// ============================================================
// 통합 프리셋 1~3 = (보조스킬 프리셋, 어빌리티 프리셋) 조합
//   카드 클릭       = 선택 (로컬 표시)
//   칩 클릭         = 그 카드의 보조스킬/어빌리티 프리셋 번호 변경 (sync)
//   [적용]          = 선택한 카드의 보조스킬 프리셋 + 어빌리티 프리셋을 한 번에 적용 (sync)
//   이미 그 조합이 적용 중이면 [적용 중] (비활성)
// 화면 버튼 [통합 프리셋] 마우스 클릭으로 창 열기/닫기 (로컬 표시)
//
// ※ 트리거 순서: UISkill, UIAbility 보다 아래에 둘 것
//   (SkillAuxAppliedPreset / SkillAuxPresetAt / SkillAuxPresetCount / SkillAuxApplyPreset,
//    AbilityPresetGrade / AbilityApplyPreset 사용)
// ============================================================

scope UIPreset initializer onInit

    static if not REFORGED_MODE then
    native DzSyncData takes string prefix, string data returns nothing
    native DzGetTriggerUIEventFrame takes nothing returns integer
    native DzFrameSetScriptByCode takes integer frame, integer eventId, code funcHandle, boolean sync returns nothing
    native DzGetTriggerSyncPlayer takes nothing returns player
    native DzGetTriggerSyncData takes nothing returns string
    native DzTriggerRegisterSyncData takes trigger t, string prefix, boolean server returns nothing
    endif

    globals
        private constant string SYNC_UNI = "UNIPS"      /* data = op,card,val  (op 0=보조스킬 칩, 1=어빌리티 칩, 2=적용) */
        private constant integer UNI_COUNT = 3          /* 통합 프리셋 수 */
        private constant integer SUB_PRESETS = 3        /* 보조스킬/어빌리티 프리셋 수 (칩 개수) */

        private constant integer UNI_W = 420
        private constant integer UNI_H = 422
        private constant integer CARD_X = 18
        private constant integer CARD_Y = 70            /* 첫 카드 y */
        private constant integer CARD_W = 384
        private constant integer CARD_H = 92
        private constant integer CARD_GAP = 102         /* 카드 간격 */
        private constant integer CHIP_X = 84            /* 카드 안 첫 칩 x */
        private constant integer CHIP_W = 38
        private constant integer CHIP_H = 24
        private constant integer CHIP_GAP = 42

        // 화면 토글 버튼 위치 (화면 우측 기준)
        private constant integer TOGGLE_W = 130
        private constant integer TOGGLE_H = 32
        private constant integer TOGGLE_RIGHT = 150     /* 화면 오른쪽 끝에서 버튼 왼쪽까지 거리 */
        private constant integer TOGGLE_TOP = 160

        private integer uniLayer = 0
        private integer uniRoot = 0
        private integer uniToggleBtn = 0
        private integer uniToggleText = 0

        private integer array cardBg            /* [card] */
        private integer array cardTitle         /* [card] */
        private integer array cardState         /* [card] ◆ 적용 중 / ◇ 변경됨 */
        private integer array auxChipBg         /* [card*SUB_PRESETS+p] */
        private integer array auxChipText
        private integer array abilChipBg
        private integer array abilChipText
        private integer array auxSumText        /* [card] */
        private integer array abilSumText       /* [card] */
        private integer uniCurText = 0
        private integer uniApplyBg = 0
        private integer uniApplyText = 0

        private integer lastBg = 0              /* createChip 결과 */
        private integer lastText = 0

        private hashtable memHash = InitHashtable()

        // 동기 상태 (sync 핸들러에서만 변경)
        private integer array uniAux            /* [pid*UNI_COUNT+card] 보조스킬 프리셋 */
        private integer array uniAbil           /* [pid*UNI_COUNT+card] 어빌리티 프리셋 */
        private integer array uniApplied        /* [pid] 마지막으로 적용한 통합 프리셋 */

        // 로컬 표시 상태
        private integer array uniSel            /* [pid] 선택한 카드 */
        boolean array uniVisible
    endglobals

    // ============================================================
    // 갱신
    // ============================================================

    // 카드 c 의 조합이 지금 실제로 적용돼 있는가
    private function isAppliedCard takes integer pid, integer c returns boolean
        local integer k = pid * UNI_COUNT + c
        if uniApplied[pid] != c then
            return false
        endif
        return uniAux[k] == SkillAuxAppliedPreset(pid) and uniAbil[k] == AbilActivePreset(pid)
    endfunction

    // 보조스킬 프리셋 요약: "장착 2/3 · 이름, 이름 외 1"
    private function auxSummary takes integer pid, integer p returns string
        local integer n = SkillAuxPresetCount(pid, p)
        local integer slot = 0
        local integer shown = 0
        local integer ridx
        local string s = "|cffBBBBBB장착 " + I2S(n) + "/" + I2S(AUX_SLOTS)
        loop
            exitwhen slot >= AUX_SLOTS or shown >= 2
            set ridx = SkillAuxPresetAt(pid, p, slot)
            if ridx >= 0 then
                if shown == 0 then
                    set s = s + " · "
                else
                    set s = s + ", "
                endif
                set s = s + AuxName(ridx)
                set shown = shown + 1
            endif
            set slot = slot + 1
        endloop
        if shown > 0 and n > shown then
            set s = s + " 외 " + I2S(n - shown)
        endif
        return s + "|r"
    endfunction

    // 어빌리티 프리셋 요약: "전체 등급 레전드리" / 비어 있음 / 미개방
    private function abilSummary takes integer pid, integer p returns string
        local integer g
        if not AbilIsUnlocked(pid) then
            return "|cffAEB9C6미개방|r"
        endif
        set g = AbilityPresetGrade(pid, p)
        if g < 0 then
            return "|cffAEB9C6비어 있음|r"
        endif
        return "|cffBBBBBB전체 등급|r " + AbilGradeColor(g) + AbilGradeName(g) + "|r"
    endfunction

    private function setChip takes integer bg, integer txt, integer num, boolean on returns nothing
        if on then
            call GUISetAlpha(bg, 255)
            call GUISetText(txt, "|cffD4AF37" + I2S(num) + "|r")
        else
            call GUISetAlpha(bg, 100)
            call GUISetText(txt, "|cff8FA8C8" + I2S(num) + "|r")
        endif
    endfunction

    private function update takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer c = 0
        local integer p
        local integer k

        if uniToggleText != 0 then
            if uniVisible[pid] then
                call GUISetText(uniToggleText, "|cff66FF99통합 프리셋|r")
            else
                call GUISetText(uniToggleText, "|cffD4AF37통합 프리셋|r")
            endif
        endif

        if not uniVisible[pid] then
            return
        endif

        loop
            exitwhen c >= UNI_COUNT
            set k = pid * UNI_COUNT + c

            if c == uniSel[pid] then
                call GUISetAlpha(cardBg[c], 230)
                call GUISetText(cardTitle[c], "|cffD4AF37통합 프리셋 " + I2S(c + 1) + "|r")
            else
                call GUISetAlpha(cardBg[c], 110)
                call GUISetText(cardTitle[c], "|cffD8D0C0통합 프리셋 " + I2S(c + 1) + "|r")
            endif

            if isAppliedCard(pid, c) then
                call GUISetText(cardState[c], "|cff66FF99◆ 적용 중|r")
            elseif uniApplied[pid] == c then
                call GUISetText(cardState[c], "|cffFF8866◇ 변경됨 (미적용)|r")
            else
                call GUISetText(cardState[c], "")
            endif

            set p = 0
            loop
                exitwhen p >= SUB_PRESETS
                call setChip(auxChipBg[c * SUB_PRESETS + p], auxChipText[c * SUB_PRESETS + p], p + 1, uniAux[k] == p)
                call setChip(abilChipBg[c * SUB_PRESETS + p], abilChipText[c * SUB_PRESETS + p], p + 1, uniAbil[k] == p)
                set p = p + 1
            endloop

            call GUISetText(auxSumText[c], auxSummary(pid, uniAux[k]))
            call GUISetText(abilSumText[c], abilSummary(pid, uniAbil[k]))
            set c = c + 1
        endloop

        call GUISetText(uniCurText, "|cff8FA8C8현재 적용|r|n|cffD8D0C0보조스킬 |r|cffFF66CC" + I2S(SkillAuxAppliedPreset(pid) + 1) + "|r|cffD8D0C0 · 어빌리티 |r|cffD4AF37" + I2S(AbilActivePreset(pid) + 1) + "|r")

        // 적용 버튼 (선택한 카드가 이미 적용 중이면 비활성 표시)
        if isAppliedCard(pid, uniSel[pid]) then
            call GUISetAlpha(uniApplyBg, 90)
            call GUISetText(uniApplyText, "|cff6f7890적용 중|r")
        else
            call GUISetAlpha(uniApplyBg, 230)
            call GUISetText(uniApplyText, "|cff66FF99적  용|r")
        endif
    endfunction

    // ============================================================
    // 입력 (로컬 → 필요한 것만 sync)
    // ============================================================

    // 화면 [통합 프리셋] 버튼 → 창 열기/닫기
    private function onToggle takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        call SfxClick(pid)
        set uniVisible[pid] = not uniVisible[pid]
        call GUIShow(uniLayer, uniVisible[pid])
        call update()
    endfunction

    private function onClose takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        call SfxClick(pid)
        set uniVisible[pid] = false
        call GUIShow(uniLayer, false)
        call update()
    endfunction

    // 외부에서 열기/닫기 (단축키 등에 연결할 때)
    function ToggleUnifiedPresetUI takes integer pid returns nothing
        set uniVisible[pid] = not uniVisible[pid]
        if GetLocalPlayer() == Player(pid) then
            call GUIShow(uniLayer, uniVisible[pid])
        endif
        call update()
    endfunction

    private function onCardClick takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        call SfxClick(pid)
        set uniSel[pid] = LoadInteger(memHash, DzGetTriggerUIEventFrame(), 0)
        call update()
    endfunction

    // 칩 버튼 값 = card*10 + p
    private function onAuxChip takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer v = LoadInteger(memHash, DzGetTriggerUIEventFrame(), 0)
        local integer c = v / 10
        local integer p = v - c * 10
        call SfxClick(pid)
        set uniSel[pid] = c
        if uniAux[pid * UNI_COUNT + c] != p then
            call DzSyncData(SYNC_UNI, "0," + I2S(c) + "," + I2S(p))
        endif
        call update()
    endfunction

    private function onAbilChip takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer v = LoadInteger(memHash, DzGetTriggerUIEventFrame(), 0)
        local integer c = v / 10
        local integer p = v - c * 10
        call SfxClick(pid)
        set uniSel[pid] = c
        if uniAbil[pid * UNI_COUNT + c] != p then
            call DzSyncData(SYNC_UNI, "1," + I2S(c) + "," + I2S(p))
        endif
        call update()
    endfunction

    private function onApplyClick takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer c = uniSel[pid]
        if isAppliedCard(pid, c) then
            return
        endif
        call SfxClick(pid)
        call DzSyncData(SYNC_UNI, "2," + I2S(c) + ",0")
    endfunction

    // ============================================================
    // 동기화
    // ============================================================
    private function onSyncUni takes nothing returns nothing
        local integer pid = GetPlayerId(DzGetTriggerSyncPlayer())
        local string d = DzGetTriggerSyncData()
        local integer op = S2I(JNStringSplit(d, ",", 0))
        local integer c = S2I(JNStringSplit(d, ",", 1))
        local integer v = S2I(JNStringSplit(d, ",", 2))
        local integer k
        if c < 0 or c >= UNI_COUNT then
            return
        endif
        set k = pid * UNI_COUNT + c

        if op == 0 then
            if v >= 0 and v < SUB_PRESETS then
                set uniAux[k] = v
            endif
        elseif op == 1 then
            if v >= 0 and v < SUB_PRESETS then
                set uniAbil[k] = v
            endif
        elseif op == 2 then
            call SkillAuxApplyPreset(pid, uniAux[k])
            if AbilIsUnlocked(pid) then
                call AbilityApplyPreset(pid, uniAbil[k])
            endif
            set uniApplied[pid] = c
            call MsgSuccess(Player(pid), "통합 프리셋 " + I2S(c + 1) + " 적용! (보조스킬 " + I2S(uniAux[k] + 1) + " · 어빌리티 " + I2S(uniAbil[k] + 1) + ")")
        endif
        call update()
    endfunction

    // ============================================================
    // UI 생성
    // ============================================================

    // 칩 1개 (bg 이미지 + 투명 버튼 + 숫자). 결과 bg/글자는 lastBg/lastText 에.
    private function createChip takes integer x, integer y, integer value, code onClick returns nothing
        local integer btn
        set lastBg = GUICreateImage(uniRoot)
        call GUISetPoint(lastBg, uniRoot, x, y)
        call GUISetSize(lastBg, CHIP_W, CHIP_H)
        call GUISetImage(lastBg, "UI_plate_none.tga")
        call GUISetAlpha(lastBg, 100)

        set btn = GUICreateButton(uniRoot)
        call GUISetPoint(btn, uniRoot, x, y)
        call GUISetSize(btn, CHIP_W, CHIP_H)
        call DzFrameSetScriptByCode(btn, 1, onClick, false)
        call SaveInteger(memHash, btn, 0, value)

        set lastText = GUICreateText(btn)
        call GUISetPointEx(lastText, GUI_DOCK_MIDDLECENTER, btn, GUI_DOCK_MIDDLECENTER, 0, 0)
        call GUISetFont(lastText, MAP_FONT_BOLD, 13)
    endfunction

    private function createCard takes integer c returns nothing
        local integer cy = CARD_Y + c * CARD_GAP
        local integer btn
        local integer t
        local integer p

        set cardBg[c] = GUICreateImage(uniRoot)
        call GUISetPoint(cardBg[c], uniRoot, CARD_X, cy)
        call GUISetSize(cardBg[c], CARD_W, CARD_H)
        call GUISetImage(cardBg[c], "UI_plate_none.tga")
        call GUISetAlpha(cardBg[c], 110)

        // 카드 전체 = 선택 버튼 (칩보다 먼저 생성 → 칩이 위에 옴)
        set btn = GUICreateButton(uniRoot)
        call GUISetPoint(btn, uniRoot, CARD_X, cy)
        call GUISetSize(btn, CARD_W, CARD_H)
        call DzFrameSetScriptByCode(btn, 1, function onCardClick, false)
        call SaveInteger(memHash, btn, 0, c)

        set cardTitle[c] = GUICreateText(uniRoot)
        call GUISetPoint(cardTitle[c], uniRoot, CARD_X + 12, cy + 6)
        call GUISetFont(cardTitle[c], MAP_FONT_BOLD, 14)

        set cardState[c] = GUICreateText(uniRoot)
        call GUISetPoint(cardState[c], uniRoot, CARD_X + 124, cy + 8)
        call GUISetFont(cardState[c], MAP_FONT_BOLD, 12)

        // 1줄: 보조스킬 프리셋
        set t = GUICreateText(uniRoot)
        call GUISetPoint(t, uniRoot, CARD_X + 12, cy + 35)
        call GUISetFont(t, MAP_FONT_BOLD, 12)
        call GUISetText(t, "|cffFF66CC보조스킬|r")
        set p = 0
        loop
            exitwhen p >= SUB_PRESETS
            call createChip(CARD_X + CHIP_X + p * CHIP_GAP, cy + 32, c * 10 + p, function onAuxChip)
            set auxChipBg[c * SUB_PRESETS + p] = lastBg
            set auxChipText[c * SUB_PRESETS + p] = lastText
            set p = p + 1
        endloop
        set auxSumText[c] = GUICreateText(uniRoot)
        call GUISetPoint(auxSumText[c], uniRoot, CARD_X + 216, cy + 36)
        call GUISetSize(auxSumText[c], 160, 16)
        call GUISetFont(auxSumText[c], MAP_FONT_LIGHT, 11)

        // 2줄: 어빌리티 프리셋
        set t = GUICreateText(uniRoot)
        call GUISetPoint(t, uniRoot, CARD_X + 12, cy + 63)
        call GUISetFont(t, MAP_FONT_BOLD, 12)
        call GUISetText(t, "|cffD4AF37어빌리티|r")
        set p = 0
        loop
            exitwhen p >= SUB_PRESETS
            call createChip(CARD_X + CHIP_X + p * CHIP_GAP, cy + 60, c * 10 + p, function onAbilChip)
            set abilChipBg[c * SUB_PRESETS + p] = lastBg
            set abilChipText[c * SUB_PRESETS + p] = lastText
            set p = p + 1
        endloop
        set abilSumText[c] = GUICreateText(uniRoot)
        call GUISetPoint(abilSumText[c], uniRoot, CARD_X + 216, cy + 64)
        call GUISetSize(abilSumText[c], 160, 16)
        call GUISetFont(abilSumText[c], MAP_FONT_LIGHT, 11)
    endfunction

    private function onMapLoad takes nothing returns nothing
        local integer bg
        local integer btn
        local integer t
        local integer c

        // 화면 토글 버튼 (항상 표시)
        set uniToggleBtn = GUICreateButton(GUIGetScreen())
        call GUISetPoint(uniToggleBtn, GUIGetScreen(), R2I(GUIGetScreenWidth()) - TOGGLE_RIGHT, TOGGLE_TOP)
        call GUISetSize(uniToggleBtn, TOGGLE_W, TOGGLE_H)
        call DzFrameSetScriptByCode(uniToggleBtn, 1, function onToggle, false)
        set bg = GUICreateImage(uniToggleBtn)
        call GUISetPoint(bg, uniToggleBtn, 0, 0)
        call GUISetSize(bg, TOGGLE_W, TOGGLE_H)
        call GUISetImage(bg, "UI_plate_none.tga")
        call GUISetAlpha(bg, 220)
        set uniToggleText = GUICreateText(uniToggleBtn)
        call GUISetPointEx(uniToggleText, GUI_DOCK_MIDDLECENTER, uniToggleBtn, GUI_DOCK_MIDDLECENTER, 0, 0)
        call GUISetFont(uniToggleText, MAP_FONT_BOLD, 14)
        call GUISetText(uniToggleText, "|cffD4AF37통합 프리셋|r")

        // 창
        set uniLayer = GUICreateContainer(GUIGetScreen())
        call GUISetPoint(uniLayer, GUIGetScreen(), 0, 0)
        call GUISetSize(uniLayer, GUIGetScreenWidth(), GUIGetScreenHeight())
        call GUIShow(uniLayer, false)

        set uniRoot = GUICreateContainer(uniLayer)
        call GUISetPoint(uniRoot, uniLayer, R2I((GUIGetScreenWidth() - UNI_W) / 2.0), R2I((GUIGetScreenHeight() - UNI_H) / 2.0))
        call GUISetSize(uniRoot, UNI_W, UNI_H)

        set bg = GUICreateImage(uniRoot)
        call GUISetPoint(bg, uniRoot, 0, 0)
        call GUISetSize(bg, UNI_W, UNI_H)
        call GUISetImage(bg, "UI_plate_none.tga")
        call GUISetAlpha(bg, 244)

        set t = GUICreateTextShadow(uniRoot)
        call GUISetPoint(t, uniRoot, 18, 12)
        call GUISetFont(t, MAP_FONT_BOLD, 18)
        call GUISetText(t, "|cffD4AF37통합 프리셋|r")

        set btn = GUICreateButton(uniRoot)
        call GUISetPoint(btn, uniRoot, UNI_W - 40, 8)
        call GUISetSize(btn, 32, 32)
        call DzFrameSetScriptByCode(btn, 1, function onClose, false)
        set bg = GUICreateImage(btn)
        call GUISetPoint(bg, btn, 0, 0)
        call GUISetSize(bg, 32, 32)
        call GUISetImage(bg, "UI_icon_close.tga")

        set t = GUICreateText(uniRoot)
        call GUISetPoint(t, uniRoot, 18, 44)
        call GUISetFont(t, MAP_FONT_LIGHT, 11)
        call GUISetText(t, "|cffBFD4E8보조스킬 · 어빌리티 프리셋을 묶어서 한 번에 적용|r")

        set c = 0
        loop
            exitwhen c >= UNI_COUNT
            call createCard(c)
            set c = c + 1
        endloop

        // 하단: 현재 적용 + [적용]
        set uniCurText = GUICreateText(uniRoot)
        call GUISetPoint(uniCurText, uniRoot, 18, UNI_H - 48)
        call GUISetFont(uniCurText, MAP_FONT_BOLD, 12)

        set btn = GUICreateButton(uniRoot)
        call GUISetPoint(btn, uniRoot, UNI_W - 18 - 120, UNI_H - 48)
        call GUISetSize(btn, 120, 34)
        call DzFrameSetScriptByCode(btn, 1, function onApplyClick, false)
        set uniApplyBg = GUICreateImage(btn)
        call GUISetPoint(uniApplyBg, btn, 0, 0)
        call GUISetSize(uniApplyBg, 120, 34)
        call GUISetImage(uniApplyBg, "UI_plate_none.tga")
        call GUISetAlpha(uniApplyBg, 90)
        set uniApplyText = GUICreateText(btn)
        call GUISetPointEx(uniApplyText, GUI_DOCK_MIDDLECENTER, btn, GUI_DOCK_MIDDLECENTER, 0, 0)
        call GUISetFont(uniApplyText, MAP_FONT_BOLD, 15)
        call GUISetText(uniApplyText, "|cff6f7890적용 중|r")
    endfunction

    private function onInit takes nothing returns nothing
        local trigger t
        local integer pid = 0
        local integer c

        // 기본 조합: 통합 N = 보조스킬 N + 어빌리티 N
        loop
            exitwhen pid >= MAX_PLAYERS
            set c = 0
            loop
                exitwhen c >= UNI_COUNT
                set uniAux[pid * UNI_COUNT + c] = c
                set uniAbil[pid * UNI_COUNT + c] = c
                set c = c + 1
            endloop
            set pid = pid + 1
        endloop

        set t = CreateTrigger()
        call TriggerRegisterTimerEvent(t, 0.60, false)
        call TriggerAddAction(t, function onMapLoad)

        set t = CreateTrigger()
        call TriggerRegisterTimerEvent(t, 0.25, true)
        call TriggerAddAction(t, function update)

        set t = CreateTrigger()
        call DzTriggerRegisterSyncData(t, SYNC_UNI, false)
        call TriggerAddAction(t, function onSyncUni)

        set t = null
    endfunction

endscope
