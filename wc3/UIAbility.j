// ============================================================
// 미소녀 키우기 - 어빌리티 UI (메이플 키우기 방식)
// ============================================================
// 3줄 + 전체등급/변환레벨 표시 + 재설정(실버) 버튼
// 개인화: 표시는 로컬, 재설정만 sync
//
// 프리셋 보기/적용 분리
//   프리셋 탭 클릭 = 보기만 (그 프리셋을 보고, 고정/재설정 가능 — 능력치는 안 바뀜)
//   [적용하기]     = 보고 있는 프리셋을 능력치에 적용 (AbilSwitchPreset + RecalcStats)
//   적용 중인 프리셋 = 백엔드 활성 프리셋(AbilActivePreset), 탭에 ◆ 표시
//   보고 있는 프리셋이 적용 중이 아니면 헤더에 [미적용], 버튼은 [적용하기] / 적용 중이면 [적용 중](비활성)
// ============================================================

scope UIAbility initializer onInit

    static if not REFORGED_MODE then
    native DzSyncData takes string prefix, string data returns nothing
    native DzGetTriggerUIEventPlayer takes nothing returns player
    native DzFrameSetScriptByCode takes integer frame, integer eventId, code funcHandle, boolean sync returns nothing
    native DzGetTriggerSyncPlayer takes nothing returns player
    native DzGetTriggerSyncData takes nothing returns string
    native DzTriggerRegisterSyncData takes trigger t, string prefix, boolean server returns nothing
    native DzGetMouseXRelative takes nothing returns integer
    native DzGetMouseYRelative takes nothing returns integer
    native DzTriggerRegisterMouseEventByCode takes trigger trig, integer btn, integer status, boolean sync, code funcHandle returns nothing
    endif

    globals
        private constant real ABIL_W = 440.0
        private constant real ABIL_H = 540.0
        private constant real PROB_W = 220.0
        private constant real PROB_H = 340.0
        private constant real OPT_W  = 200.0
        private constant string SYNC_CMD_REROLL = "ABILRR"
        private constant string SYNC_CMD_PRESET = "ABILPS"   /* 프리셋 적용 (data=pid,preset) */
        private constant string SYNC_CMD_VIEW = "ABILVW"     /* 프리셋 보기 (data=pid,preset) */

        // 프리셋 보기 (동기 상태 — sync 핸들러에서만 변경)
        private integer array abilViewRaw          /* [pid] 보고 있는 프리셋+1 (0 = 적용 중인 프리셋을 봄) */

        // 프리셋 적용 버튼 (헤더 우측)
        private integer abilApplyBtn = 0
        private integer abilApplyBg = 0
        private integer abilApplyText = 0

        // 프리셋 탭 버튼 (가로 배치, 헤더 아래)
        private integer array abilPresetBtn        /* [preset] */
        private integer array abilPresetBg         /* [preset] */
        private integer array abilPresetText       /* [preset] */
        private integer array abilPresetUnder      /* [preset] 선택 탭 하단 언더라인 */

        private integer abilLayer = 0
        private integer abilRoot = 0
        private integer abilTitle = 0
        private integer abilCloseBtn = 0
        private integer abilHeadText = 0
        private integer array abilLineText
        private integer abilLockText = 0
        private integer abilSilverText = 0
        private integer abilRerollBtn = 0
        private integer abilRerollText = 0
        private integer abilGuideText = 0
        private integer array abilLineBtn          /* [line] 줄 클릭(고정 토글) 버튼 */
        private boolean array lineLocked           /* [(pid*ABIL_PRESETS+preset)*ABIL_LINES+line] 프리셋별 고정 상태 */

        // 확률 가이드 패널 (우측, 변환 레벨별 등급 확률)
        private integer abilProbRoot = 0
        private integer abilProbTitle = 0
        private integer abilProbSub = 0
        private integer array abilProbRow          /* [grade] */
        private integer abilProbNote = 0

        // 창 드래그 이동
        private integer abilCaptionBar = 0
        private integer abilX = 0
        private integer abilY = 0
        private string hovering = null
        private string dragging = null

        // 자동 재설정 (목표 등급까지 반복)
        private integer abilAutoBtn = 0
        private integer abilAutoText = 0
        private integer array abilTargetGrade   /* [pid] 목표 전체 등급 (기본 유니크) */
        private boolean array abilAutoActive    /* [pid] 자동 진행 (소유 클라에서만 의미) */
        private boolean array abilAutoPending   /* [pid] 재설정 sync 처리 대기 중 */

        // 목표 등급 선택 패널 (우측, 등급 확률 패널 아래 상시 표시)
        private integer abilGradePanel = 0
        private integer abilGradePanelTitle = 0
        private integer abilGradePanelSub = 0
        private integer array abilGradeRowBtn    /* [grade] */
        private integer array abilGradeRowText   /* [grade] */

        // 목표 옵션 필터 패널 (최우측, 다중선택 OR — mask 0 = 전체/필터없음)
        private integer abilOptPanel = 0
        private integer abilOptPanelTitle = 0
        private integer abilOptPanelSub = 0
        private integer abilOptAllBtn = 0
        private integer abilOptAllText = 0
        private integer array abilOptRowBtn      /* [opt] */
        private integer array abilOptRowText     /* [opt] */
        private integer array abilOptMask        /* [pid] 선택 옵션 비트마스크 (0=전체) */

        boolean array abilVisible
    endglobals

    // 보고 있는 프리셋 (적용 중인 프리셋과 다를 수 있음)
    private function viewPreset takes integer pid returns integer
        if abilViewRaw[pid] <= 0 then
            return AbilActivePreset(pid)
        endif
        return abilViewRaw[pid] - 1
    endfunction

    // 보고 있는 프리셋을 잠깐 활성으로 바꿔 읽기/재설정한 뒤 peekEnd 로 되돌린다.
    //   백엔드 Abil* 함수는 활성 프리셋만 읽으므로 이 방식으로 미적용 프리셋을 다룸.
    //   같은 함수 안에서 바로 되돌리고 RecalcStats 를 부르지 않으므로 능력치는 그대로.
    //   (AbilSwitchPreset 이 인덱스/데이터 전환만 하고 스탯·메시지 등 부수효과가 없어야 함)
    //   반환값 = 원래 적용 중인 프리셋
    private function peekBegin takes integer pid returns integer
        local integer applied = AbilActivePreset(pid)
        local integer v = viewPreset(pid)
        if v != applied then
            call AbilSwitchPreset(pid, v)
        endif
        return applied
    endfunction

    private function peekEnd takes integer pid, integer applied returns nothing
        if AbilActivePreset(pid) != applied then
            call AbilSwitchPreset(pid, applied)
        endif
    endfunction

    // 보고 있는 프리셋 기준 잠금 배열 베이스 (lineLocked가 프리셋별로 유지되도록)
    private function lockBase takes integer pid returns integer
        return (pid * ABIL_PRESETS + viewPreset(pid)) * ABIL_LINES
    endfunction

    // 줄 전체 표기 (등급 컬러 + 옵션)
    private function LineFull takes integer pid, integer line returns string
        local integer g = AbilLineGrade(pid, line)
        return AbilGradeColor(g) + "[" + AbilGradeName(g) + "]|r  |cffD8D0C0" + AbilLineText(pid, line) + "|r"
    endfunction

    // 확률 가이드 패널 갱신 (현재 변환 레벨 기준 등급별 확률)
    private function refreshProb takes integer pid returns nothing
        local integer conv = AbilConvLevel(pid)
        local integer cap = AbilConvCap(pid)
        local integer grade = 0
        local integer p
        call GUISetText(abilProbSub, "|cffBFE0FF변환 레벨 " + I2S(conv) + "|r")
        call GUISetText(abilProbNote, "|cffBFD4E8재설정할수록 변환 레벨이 올라|n상위 등급 확률이 증가합니다.|n(확률 적용 상한 " + I2S(cap) + ")|r")
        loop
            exitwhen grade >= ABIL_GRADES
            set p = AbilGradeChancePermille(conv, cap, grade)
            call GUISetText(abilProbRow[grade], AbilGradeColor(grade) + AbilGradeName(grade) + "|r  |cffD8D0C0" + I2S(p / 10) + "." + I2S(p - (p / 10) * 10) + "%|r")
            set grade = grade + 1
        endloop
    endfunction

    // opt번째 비트값 (2^opt)
    private function optBit takes integer opt returns integer
        local integer bit = 1
        local integer i = 0
        loop
            exitwhen i >= opt
            set bit = bit * 2
            set i = i + 1
        endloop
        return bit
    endfunction

    // 선택된 옵션 필터 설명 (전체/필터없음이면 빈 문자열)
    private function optMaskDesc takes integer pid returns string
        local integer mask = abilOptMask[pid]
        local integer i = 0
        local string s = ""
        if mask == 0 then
            return ""
        endif
        loop
            exitwhen i >= OPT_COUNT
            if AbilLockBit(mask, i) then
                if s == "" then
                    set s = opt_name[i]
                else
                    set s = s + "/" + opt_name[i]
                endif
            endif
            set i = i + 1
        endloop
        return s
    endfunction

    // 자동 정지 조건을 만족하는 줄 번호 (없으면 -1)
    //   조건: 잠금 안 된 줄 + 목표 등급 이상 + (옵션 필터 없거나 선택 옵션 중 하나)
    //   ※ 보고 있는 프리셋 기준 — 호출 측에서 peekBegin/peekEnd 로 감쌀 것
    private function autoGoalLine takes integer pid returns integer
        local integer line = 0
        local integer mask = abilOptMask[pid]
        loop
            exitwhen line >= ABIL_LINES
            if not lineLocked[lockBase(pid) + line] then
                if AbilLineGrade(pid, line) >= abilTargetGrade[pid] then
                    if mask == 0 then
                        return line
                    elseif AbilLockBit(mask, AbilLineOpt(pid, line)) then
                        return line
                    endif
                endif
            endif
            set line = line + 1
        endloop
        return -1
    endfunction

    // 프리셋 탭 버튼 상태 갱신 — 회색 bg 위라 비활성도 밝은 톤
    //   보고 있는 탭 = bg 강조 + 언더라인 / 적용 중인 탭 = ◆ + 초록 글자 / 빈 프리셋 = 슬레이트 글자
    private function refreshPresetBtns takes integer pid returns nothing
        local integer i = 0
        local integer view = viewPreset(pid)
        local integer applied = AbilActivePreset(pid)
        loop
            exitwhen i >= ABIL_PRESETS
            if i == view then
                call GUISetAlpha(abilPresetBg[i], 255)
                call GUIShow(abilPresetUnder[i], true)
            else
                call GUISetAlpha(abilPresetBg[i], 140)
                call GUIShow(abilPresetUnder[i], false)
            endif
            if i == applied then
                call GUISetText(abilPresetText[i], "|cff66FF99◆ 프리셋 " + I2S(i + 1) + "|r")
            elseif AbilPresetRolled(pid, i) then
                call GUISetText(abilPresetText[i], "|cffD8D0C0프리셋 " + I2S(i + 1) + "|r")
            else
                call GUISetText(abilPresetText[i], "|cffAEB9C6프리셋 " + I2S(i + 1) + "|r")
            endif
            set i = i + 1
        endloop

        // 적용 버튼 (보고 있는 프리셋이 이미 적용 중이면 비활성 표시)
        if view == applied then
            call GUISetAlpha(abilApplyBg, 90)
            call GUISetText(abilApplyText, "|cff6f7890적용 중|r")
        else
            call GUISetAlpha(abilApplyBg, 230)
            call GUISetText(abilApplyText, "|cff66FF99적용하기|r")
        endif
    endfunction

    private function update takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer g
        local integer line
        local integer mask = 0
        local integer bit
        local integer i
        local string marker
        local integer applied
        local string unapplied = ""

        if not abilVisible[pid] then
            return
        endif

        call refreshProb(pid)

        // 개방은 AddExp(전 클라 동기)에서 처리 — UI에서 롤하면 디싱크
        if not AbilIsUnlocked(pid) then
            call GUIShow(abilLockText, true)
            call GUIShow(abilHeadText, false)
            call GUIShow(abilSilverText, false)
            call GUIShow(abilRerollBtn, false)
            call GUIShow(abilAutoBtn, false)
            call GUIShow(abilGradePanel, false)
            call GUIShow(abilOptPanel, false)
            set i = 0
            loop
                exitwhen i >= ABIL_PRESETS
                call GUIShow(abilPresetBtn[i], false)
                set i = i + 1
            endloop
            call GUIShow(abilApplyBtn, false)
            set line = 0
            loop
                exitwhen line >= ABIL_LINES
                call GUIShow(abilLineText[line], false)
                set line = line + 1
            endloop
            call GUISetText(abilLockText, "|cffFFE0A0Lv." + I2S(ABIL_UNLOCK_LEVEL) + " 달성 시 개방됩니다|n현재 Lv." + I2S(player_level[pid]) + "|r")
            return
        endif

        call GUIShow(abilLockText, false)
        call GUIShow(abilHeadText, true)
        call GUIShow(abilSilverText, true)
        call GUIShow(abilRerollBtn, true)
        call GUIShow(abilAutoBtn, true)
        call GUIShow(abilGradePanel, true)
        call GUIShow(abilOptPanel, true)

        set i = 0
        loop
            exitwhen i >= ABIL_PRESETS
            call GUIShow(abilPresetBtn[i], true)
            set i = i + 1
        endloop
        call GUIShow(abilApplyBtn, true)
        call refreshPresetBtns(pid)

        if viewPreset(pid) != AbilActivePreset(pid) then
            set unapplied = "  |cffFF8866[미적용]|r"
        endif

        // 여기서부터 reroll 비용까지는 보고 있는 프리셋 기준으로 읽음
        set applied = peekBegin(pid)

        if not AbilPresetRolled(pid, AbilActivePreset(pid)) then
            // 빈 프리셋: 안내만 표시, 재설정으로 생성
            call GUISetText(abilHeadText, "|cffFFE0A0비어 있는 프리셋|r    |cffBFE0FF변환 레벨 " + I2S(AbilConvLevel(pid)) + "|r" + unapplied)
            set line = 0
            loop
                exitwhen line >= ABIL_LINES
                call GUIShow(abilLineText[line], line == 0)
                set line = line + 1
            endloop
            call GUISetText(abilLineText[0], "|cffBFD4E8이 프리셋은 비어 있습니다.|n아래 [재설정]으로 어빌리티를 생성하세요.|r")
            set mask = 0
        else
            set g = AbilOverallGrade(pid)
            call GUISetText(abilHeadText, "전체 등급 " + AbilGradeColor(g) + AbilGradeName(g) + "|r    |cffBFE0FF변환 레벨 " + I2S(AbilConvLevel(pid)) + "|r" + unapplied)

            set line = 0
            set bit = 1
            loop
                exitwhen line >= ABIL_LINES
                call GUIShow(abilLineText[line], true)
                if lineLocked[lockBase(pid) + line] then
                    call GUISetText(abilLineText[line], "|cffD4AF37[고정]|r " + LineFull(pid, line))
                    set mask = mask + bit
                else
                    call GUISetText(abilLineText[line], LineFull(pid, line))
                endif
                set bit = bit * 2
                set line = line + 1
            endloop
        endif

        call GUISetText(abilSilverText, "|cffE8E8E8보유 실버 |r|cffD4AF37" + SilverFmt(pid) + "|r")
        call GUISetText(abilRerollText, "|cffD8D0C0재설정|r  |cffD4AF37" + I2S(AbilRerollCost(pid, mask)) + " 실버|r")

        call peekEnd(pid, applied)

        if abilAutoActive[pid] then
            call GUISetText(abilAutoText, "|cffFF8888■ 자동 정지|r")
        else
            call GUISetText(abilAutoText, "|cff88FF88▶ 자동 재설정|r")
        endif

        // 목표 등급 패널 각 행 — 현재 선택 등급 강조
        set i = 1
        loop
            exitwhen i >= ABIL_GRADES
            if i == abilTargetGrade[pid] then
                set marker = "|cffD8D0C0▶  |r"
            else
                set marker = "    "
            endif
            call GUISetText(abilGradeRowText[i], marker + AbilGradeColor(i) + AbilGradeName(i) + "|r")
            set i = i + 1
        endloop

        // 목표 옵션 필터 — 선택된 옵션 강조 (mask 0 = 전체)
        // 회색 bg 위라 비선택도 밝은 슬레이트색 사용 (회색 텍스트 금지)
        if abilOptMask[pid] == 0 then
            call GUISetText(abilOptAllText, "|cff66FF99[V] 전체 (아무 옵션)|r")
        else
            call GUISetText(abilOptAllText, "|cffAEB9C6[  ] 전체 (아무 옵션)|r")
        endif
        set i = 0
        loop
            exitwhen i >= OPT_COUNT
            if AbilLockBit(abilOptMask[pid], i) then
                call GUISetText(abilOptRowText[i], "|cff66FF99[V] " + opt_name[i] + "|r")
            else
                call GUISetText(abilOptRowText[i], "|cffAEB9C6[  ] " + opt_name[i] + "|r")
            endif
            set i = i + 1
        endloop
    endfunction

    function ToggleAbilityUI takes integer pid returns nothing
        set abilVisible[pid] = not abilVisible[pid]
        if GetLocalPlayer() == Player(pid) then
            call GUIShow(abilLayer, abilVisible[pid])
        endif
        call update()
    endfunction

    function CloseAbilityUI takes integer pid returns nothing
        if abilVisible[pid] then
            set abilVisible[pid] = false
            if GetLocalPlayer() == Player(pid) then
                call GUIShow(abilLayer, false)
            endif
        endif
    endfunction

    private function onCloseClick takes nothing returns nothing
        local integer pid = GetPlayerId(DzGetTriggerUIEventPlayer())
        call SfxClick(pid)
        set abilVisible[pid] = false
        if GetLocalPlayer() == Player(pid) then
            call GUIShow(abilLayer, false)
        endif
    endfunction

    // 줄 클릭 → 고정 토글 (로컬 상태, 재설정 시 마스크로 전송)
    private function toggleLock takes integer line returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        call SfxClick(pid)
        if not AbilIsUnlocked(pid) then
            return
        endif
        if not AbilPresetRolled(pid, viewPreset(pid)) then
            return
        endif
        set lineLocked[lockBase(pid) + line] = not lineLocked[lockBase(pid) + line]
        call update()
    endfunction
    private function onLock0 takes nothing returns nothing
        call toggleLock(0)
    endfunction
    private function onLock1 takes nothing returns nothing
        call toggleLock(1)
    endfunction
    private function onLock2 takes nothing returns nothing
        call toggleLock(2)
    endfunction
    private function onLock3 takes nothing returns nothing
        call toggleLock(3)
    endfunction
    private function onLock4 takes nothing returns nothing
        call toggleLock(4)
    endfunction

    private function onRerollClick takes nothing returns nothing
        local integer pid = GetPlayerId(DzGetTriggerUIEventPlayer())
        local integer mask = 0
        local integer line = 0
        local integer bit = 1
        call SfxClick(pid)
        loop
            exitwhen line >= ABIL_LINES
            if lineLocked[lockBase(pid) + line] then
                set mask = mask + bit
            endif
            set bit = bit * 2
            set line = line + 1
        endloop
        call DzSyncData(SYNC_CMD_REROLL, I2S(pid) + "," + I2S(mask) + "," + I2S(viewPreset(pid)))
    endfunction

    private function onSyncReroll takes nothing returns nothing
        local player p = DzGetTriggerSyncPlayer()
        local string d = DzGetTriggerSyncData()
        local integer pid = GetPlayerId(p)
        local integer mask = S2I(JNStringSplit(d, ",", 1))
        local integer tagPreset = S2I(JNStringSplit(d, ",", 2))
        local integer st
        local integer g
        local integer ml
        local integer applied
        local string note = ""
        // 전송 시점의 보고 있는 프리셋과 수신 시점의 보고 있는 프리셋이 다르면 무시
        //   (자동 재설정 중 프리셋 전환 → 늦게 도착한 리롤이 다른 프리셋을 덮어쓰는 사고 방지)
        //   보기/적용 프리셋은 sync로만 바뀌는 동기 상태라 전 클라 동일 판정 = 디싱크 없음
        if tagPreset != viewPreset(pid) then
            set abilAutoPending[pid] = false
            set p = null
            return
        endif
        if tagPreset != AbilActivePreset(pid) then
            set note = " |cffFF8866(미적용 프리셋)|r"
        endif
        // 보고 있는 프리셋을 재설정 (미적용 프리셋이면 능력치는 그대로)
        set applied = peekBegin(pid)
        set st = AbilityReroll(pid, mask)
        set abilAutoPending[pid] = false
        if st == 0 then
            if abilAutoActive[pid] then
                // 자동 진행 중에는 개별 성공 메시지 생략, 목표(등급+옵션) 도달 시에만 완료 알림
                set ml = autoGoalLine(pid)
                if ml >= 0 then
                    set abilAutoActive[pid] = false
                    call MsgSuccess(Player(pid), "자동 재설정 완료! " + LineFull(pid, ml) + note)
                endif
            else
                set g = AbilOverallGrade(pid)
                call MsgSuccess(Player(pid), "어빌리티 재설정! 전체 등급 " + AbilGradeColor(g) + AbilGradeName(g) + "|r" + note)
            endif
        elseif st == 1 then
            set abilAutoActive[pid] = false
            call MsgError(Player(pid), "Lv." + I2S(ABIL_UNLOCK_LEVEL) + " 이상에서 개방됩니다.")
        elseif st == 3 then
            set abilAutoActive[pid] = false
            call MsgError(Player(pid), "모든 줄이 고정되어 재설정할 수 없습니다.")
        else
            set abilAutoActive[pid] = false
            call MsgError(Player(pid), "실버가 부족합니다.")
        endif
        call peekEnd(pid, applied)
        // 적용 중인 프리셋을 재설정했을 때만 능력치 갱신
        if st == 0 and tagPreset == applied then
            call RecalcStats(pid)
        endif
        call update()
        set p = null
    endfunction

    // ============================================================
    // 프리셋 전환 (활성 프리셋 변경 → 스탯 재적용, 전 클라 동기 필수)
    // ============================================================
    // 활성 프리셋 변경 + 자동 정지 + 스탯 재계산 (sync 핸들러에서 전 클라 실행)
    //   잠금 상태는 프리셋별로 유지 (lineLocked가 프리셋 단위 인덱싱) — 초기화하지 않음
    private function doPresetSwitch takes integer pid, integer preset returns nothing
        call AbilSwitchPreset(pid, preset)
        set abilAutoActive[pid] = false
        set abilAutoPending[pid] = false
        call RecalcStats(pid)
    endfunction

    // ============================================================
    // 통합 프리셋(UIPreset)에서 쓰는 공개 함수
    // ============================================================
    // 프리셋 p 의 전체 등급 (-1 = 미개방/빈 프리셋). peekBegin 과 같은 방식으로 잠깐 바꿔 읽고 되돌림
    function AbilityPresetGrade takes integer pid, integer p returns integer
        local integer applied
        local integer g
        if not AbilIsUnlocked(pid) or not AbilPresetRolled(pid, p) then
            return -1
        endif
        set applied = AbilActivePreset(pid)
        if p != applied then
            call AbilSwitchPreset(pid, p)
        endif
        set g = AbilOverallGrade(pid)
        if p != applied then
            call AbilSwitchPreset(pid, applied)
        endif
        return g
    endfunction

    // 어빌리티 프리셋 p 적용 + 어빌리티창도 그 프리셋을 보게 함 (sync 핸들러 안에서만 호출)
    function AbilityApplyPreset takes integer pid, integer p returns boolean
        if not AbilIsUnlocked(pid) or p < 0 or p >= ABIL_PRESETS then
            return false
        endif
        set abilViewRaw[pid] = 0
        if p != AbilActivePreset(pid) then
            call doPresetSwitch(pid, p)
        endif
        return true
    endfunction

    // [적용하기] sync — 보고 있던 프리셋을 능력치에 적용
    private function onSyncPreset takes nothing returns nothing
        local string d = DzGetTriggerSyncData()
        local integer pid = GetPlayerId(DzGetTriggerSyncPlayer())
        local integer preset = S2I(JNStringSplit(d, ",", 1))
        if preset < 0 or preset >= ABIL_PRESETS then
            return
        endif
        if preset == AbilActivePreset(pid) then
            return
        endif
        call doPresetSwitch(pid, preset)
        set abilViewRaw[pid] = 0   /* 적용 후에는 적용 중인 프리셋을 봄 */
        call MsgSystem(Player(pid), "프리셋 " + I2S(preset + 1) + " 을(를) 적용했습니다.")
        call update()
    endfunction

    // 프리셋 탭 sync — 보는 프리셋만 변경 (능력치 그대로)
    private function onSyncView takes nothing returns nothing
        local string d = DzGetTriggerSyncData()
        local integer pid = GetPlayerId(DzGetTriggerSyncPlayer())
        local integer preset = S2I(JNStringSplit(d, ",", 1))
        if preset < 0 or preset >= ABIL_PRESETS then
            return
        endif
        if preset == AbilActivePreset(pid) then
            set abilViewRaw[pid] = 0
        else
            set abilViewRaw[pid] = preset + 1
        endif
        set abilAutoActive[pid] = false
        set abilAutoPending[pid] = false
        call update()
    endfunction

    // [적용하기] 클릭 (로컬 → sync 전송). 이미 적용 중이면 무시
    private function onApplyClick takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer view = viewPreset(pid)
        if not AbilIsUnlocked(pid) then
            return
        endif
        if view == AbilActivePreset(pid) then
            return
        endif
        call SfxClick(pid)
        call DzSyncData(SYNC_CMD_PRESET, I2S(pid) + "," + I2S(view))
    endfunction

    // 프리셋 탭 클릭 (로컬 → sync 전송). 보고 있는 프리셋이면 무시
    private function pickPreset takes integer preset returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        call SfxClick(pid)
        if not AbilIsUnlocked(pid) then
            return
        endif
        if preset == viewPreset(pid) then
            return
        endif
        // 전환 sync가 왕복하기 전에 autoTick이 리롤을 더 보내지 않도록 즉시 로컬 정지
        //   (abilAutoActive/Pending은 소유 클라 전용 UI 상태라 로컬 변경해도 디싱크 없음)
        if abilAutoActive[pid] then
            set abilAutoActive[pid] = false
            call MsgSystem(Player(pid), "프리셋 전환으로 자동 재설정을 멈췄습니다.")
        endif
        set abilAutoPending[pid] = false
        call DzSyncData(SYNC_CMD_VIEW, I2S(pid) + "," + I2S(preset))
    endfunction
    private function onPreset0 takes nothing returns nothing
        call pickPreset(0)
    endfunction
    private function onPreset1 takes nothing returns nothing
        call pickPreset(1)
    endfunction
    private function onPreset2 takes nothing returns nothing
        call pickPreset(2)
    endfunction

    // ============================================================
    // 자동 재설정 (목표 등급까지 반복)
    // ============================================================

    // 목표 등급 패널에서 직접 선택 (노멀은 항상 충족이라 레어~미스틱만)
    private function pickGrade takes integer grade returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        call SfxClick(pid)
        if not AbilIsUnlocked(pid) then
            return
        endif
        set abilTargetGrade[pid] = grade
        call update()
    endfunction
    private function onPick1 takes nothing returns nothing
        call pickGrade(1)
    endfunction
    private function onPick2 takes nothing returns nothing
        call pickGrade(2)
    endfunction
    private function onPick3 takes nothing returns nothing
        call pickGrade(3)
    endfunction
    private function onPick4 takes nothing returns nothing
        call pickGrade(4)
    endfunction
    private function onPick5 takes nothing returns nothing
        call pickGrade(5)
    endfunction

    // 옵션 필터 토글 (다중선택 OR)
    private function toggleOpt takes integer opt returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer bit
        call SfxClick(pid)
        if not AbilIsUnlocked(pid) then
            return
        endif
        set bit = optBit(opt)
        if AbilLockBit(abilOptMask[pid], opt) then
            set abilOptMask[pid] = abilOptMask[pid] - bit
        else
            set abilOptMask[pid] = abilOptMask[pid] + bit
        endif
        call update()
    endfunction
    private function onOptAll takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        call SfxClick(pid)
        if not AbilIsUnlocked(pid) then
            return
        endif
        set abilOptMask[pid] = 0
        call update()
    endfunction
    private function onOpt0 takes nothing returns nothing
        call toggleOpt(0)
    endfunction
    private function onOpt1 takes nothing returns nothing
        call toggleOpt(1)
    endfunction
    private function onOpt2 takes nothing returns nothing
        call toggleOpt(2)
    endfunction
    private function onOpt3 takes nothing returns nothing
        call toggleOpt(3)
    endfunction
    private function onOpt4 takes nothing returns nothing
        call toggleOpt(4)
    endfunction
    private function onOpt5 takes nothing returns nothing
        call toggleOpt(5)
    endfunction
    private function onOpt6 takes nothing returns nothing
        call toggleOpt(6)
    endfunction
    private function onOpt7 takes nothing returns nothing
        call toggleOpt(7)
    endfunction
    private function onOpt8 takes nothing returns nothing
        call toggleOpt(8)
    endfunction
    private function onOpt9 takes nothing returns nothing
        call toggleOpt(9)
    endfunction
    private function onOpt10 takes nothing returns nothing
        call toggleOpt(10)
    endfunction
    private function onOpt11 takes nothing returns nothing
        call toggleOpt(11)
    endfunction
    private function onOpt12 takes nothing returns nothing
        call toggleOpt(12)
    endfunction

    // opt번째 버튼에 핸들러 바인딩 (onMapLoad에서 호출)
    private function bindOptRow takes integer opt returns nothing
        if opt == 0 then
            call DzFrameSetScriptByCode(abilOptRowBtn[0], 1, function onOpt0, false)
        elseif opt == 1 then
            call DzFrameSetScriptByCode(abilOptRowBtn[1], 1, function onOpt1, false)
        elseif opt == 2 then
            call DzFrameSetScriptByCode(abilOptRowBtn[2], 1, function onOpt2, false)
        elseif opt == 3 then
            call DzFrameSetScriptByCode(abilOptRowBtn[3], 1, function onOpt3, false)
        elseif opt == 4 then
            call DzFrameSetScriptByCode(abilOptRowBtn[4], 1, function onOpt4, false)
        elseif opt == 5 then
            call DzFrameSetScriptByCode(abilOptRowBtn[5], 1, function onOpt5, false)
        elseif opt == 6 then
            call DzFrameSetScriptByCode(abilOptRowBtn[6], 1, function onOpt6, false)
        elseif opt == 7 then
            call DzFrameSetScriptByCode(abilOptRowBtn[7], 1, function onOpt7, false)
        elseif opt == 8 then
            call DzFrameSetScriptByCode(abilOptRowBtn[8], 1, function onOpt8, false)
        elseif opt == 9 then
            call DzFrameSetScriptByCode(abilOptRowBtn[9], 1, function onOpt9, false)
        elseif opt == 10 then
            call DzFrameSetScriptByCode(abilOptRowBtn[10], 1, function onOpt10, false)
        elseif opt == 11 then
            call DzFrameSetScriptByCode(abilOptRowBtn[11], 1, function onOpt11, false)
        else
            call DzFrameSetScriptByCode(abilOptRowBtn[12], 1, function onOpt12, false)
        endif
    endfunction

    private function onAutoClick takes nothing returns nothing
        local integer pid = GetPlayerId(DzGetTriggerUIEventPlayer())
        local integer applied
        local integer goal
        call SfxClick(pid)
        if not AbilIsUnlocked(pid) then
            return
        endif
        if abilAutoActive[pid] then
            set abilAutoActive[pid] = false
            call MsgSystem(Player(pid), "자동 재설정을 멈췄습니다.")
            call update()
            return
        endif
        set applied = peekBegin(pid)
        set goal = autoGoalLine(pid)
        call peekEnd(pid, applied)
        if goal >= 0 then
            call MsgInfo(Player(pid), "이미 잠금 안 된 줄에 목표 조건을 만족하는 옵션이 있습니다.")
            return
        endif
        set abilAutoActive[pid] = true
        set abilAutoPending[pid] = false
        if optMaskDesc(pid) == "" then
            call MsgSystem(Player(pid), AbilGradeColor(abilTargetGrade[pid]) + AbilGradeName(abilTargetGrade[pid]) + "|r 이상이 나올 때까지 자동 재설정합니다.")
        else
            call MsgSystem(Player(pid), AbilGradeColor(abilTargetGrade[pid]) + AbilGradeName(abilTargetGrade[pid]) + "|r 이상 + 옵션[|cffFFFFFF" + optMaskDesc(pid) + "|r] 이(가) 나올 때까지 자동 재설정합니다.")
        endif
        call update()
    endfunction

    // 0.12초 주기 구동 — 각 클라는 자기 플레이어(pid)만 진행
    private function autoTick takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer mask = 0
        local integer locked = 0
        local integer line = 0
        local integer bit = 1
        local integer applied
        local integer goal
        local integer cost
        if not abilAutoActive[pid] then
            return
        endif
        if abilAutoPending[pid] then
            return
        endif
        if not AbilIsUnlocked(pid) then
            set abilAutoActive[pid] = false
            return
        endif
        set applied = peekBegin(pid)
        set goal = autoGoalLine(pid)
        call peekEnd(pid, applied)
        if goal >= 0 then
            set abilAutoActive[pid] = false
            return
        endif
        loop
            exitwhen line >= ABIL_LINES
            if lineLocked[lockBase(pid) + line] then
                set mask = mask + bit
                set locked = locked + 1
            endif
            set bit = bit * 2
            set line = line + 1
        endloop
        if locked >= ABIL_LINES then
            set abilAutoActive[pid] = false
            call MsgError(Player(pid), "모든 줄이 고정되어 재설정할 수 없습니다.")
            return
        endif
        set applied = peekBegin(pid)
        set cost = AbilRerollCost(pid, mask)
        call peekEnd(pid, applied)
        if SilverGet(pid) < cost then
            set abilAutoActive[pid] = false
            call MsgError(Player(pid), "실버가 부족하여 자동 재설정을 멈춥니다.")
            return
        endif
        set abilAutoPending[pid] = true
        call DzSyncData(SYNC_CMD_REROLL, I2S(pid) + "," + I2S(mask) + "," + I2S(viewPreset(pid)))
    endfunction

    // ============================================================
    // 캡션 드래그 이동 (ui-shop 패턴)
    // ============================================================
    private function mouseEnterCaption takes nothing returns nothing
        set hovering = "captionBar"
        call SfxHover(GetPlayerId(GetLocalPlayer()))
    endfunction
    private function mouseLeaveCaption takes nothing returns nothing
        if hovering == "captionBar" then
            set hovering = null
        endif
    endfunction
    private function startDrag takes nothing returns nothing
        local real cursorX = 1.0 * DzGetMouseXRelative() / gx_localScreenWidth * GUIGetScreenWidth()
        local real cursorY = 1.0 * DzGetMouseYRelative() / gx_localScreenHeight * GUIGetScreenHeight()
        local real offsetX = cursorX - abilX
        local real offsetY = cursorY - abilY
        set dragging = "captionBar"
        set gx_cursorOffsetX = -0.8 * offsetX / GUIGetScreenWidth()
        set gx_cursorOffsetY = 0.6 * offsetY / GUIGetScreenHeight()
        call GUIClearAllPoints(abilRoot)
        call GUISetPoint(abilRoot, gx_cursorFrame, 0, 0)
    endfunction
    private function stopDrag takes nothing returns nothing
        local real offsetX = gx_cursorOffsetX / 0.8 * GUIGetScreenWidth()
        local real offsetY = gx_cursorOffsetY / -0.6 * GUIGetScreenHeight()
        local real cursorX = 1.0 * DzGetMouseXRelative() / gx_localScreenWidth * GUIGetScreenWidth()
        local real cursorY = 1.0 * DzGetMouseYRelative() / gx_localScreenHeight * GUIGetScreenHeight()
        set dragging = null
        set abilX = R2I(cursorX + offsetX)
        set abilY = R2I(cursorY + offsetY)
        call GUIClearAllPoints(abilRoot)
        call GUISetPoint(abilRoot, abilLayer, abilX, abilY)
    endfunction
    private function onLMBDown takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        if not abilVisible[pid] then
            return
        endif
        if hovering == "captionBar" and dragging == null then
            call startDrag()
        endif
    endfunction
    private function onLMBUp takes nothing returns nothing
        if dragging == "captionBar" then
            call stopDrag()
        endif
    endfunction

    // ============================================================
    // UI 생성
    // ============================================================
    private function onMapLoad takes nothing returns nothing
        local integer i
        local integer bg
        local integer line
        local integer pid

        set abilLayer = GUICreateContainer(GUIGetScreen())
        call GUISetPoint(abilLayer, GUIGetScreen(), 0, 0)
        call GUISetSize(abilLayer, GUIGetScreenWidth(), GUIGetScreenHeight())
        call GUIShow(abilLayer, false)

        set abilX = R2I((GUIGetScreenWidth() - (ABIL_W + 10.0 + PROB_W + 10.0 + OPT_W)) / 2.0)
        set abilY = R2I((GUIGetScreenHeight() - ABIL_H) / 2.0)
        set abilRoot = GUICreateContainer(abilLayer)
        call GUISetPoint(abilRoot, abilLayer, abilX, abilY)
        // 컨테이너 바운드를 우측 등급확률/목표/옵션 패널까지 포함 (바운드 밖이면 그 안의 버튼 입력이 클리핑됨)
        call GUISetSize(abilRoot, ABIL_W + 10.0 + PROB_W + 10.0 + OPT_W, 548.0)

        set bg = GUICreateImage(abilRoot)
        call GUISetPoint(bg, abilRoot, 0, 0)
        call GUISetSize(bg, ABIL_W, ABIL_H)
        call GUISetImage(bg, "UI_plate_none.tga")
        call GUISetAlpha(bg, 244)

        set abilTitle = GUICreateTextShadow(abilRoot)
        call GUISetPoint(abilTitle, abilRoot, 18, 12)
        call GUISetFont(abilTitle, MAP_FONT_BOLD, 18)
        call GUISetText(abilTitle, "|cffD4AF37어빌리티|r")

        // 캡션바 (드래그 이동 핸들) — 닫기 버튼 영역은 비워둠
        set abilCaptionBar = GUICreateButton(abilRoot)
        call GUISetPoint(abilCaptionBar, abilRoot, 0, 0)
        call GUISetSize(abilCaptionBar, R2I(ABIL_W) - 48, 40)
        call DzFrameSetScriptByCode(abilCaptionBar, 2, function mouseEnterCaption, false)
        call DzFrameSetScriptByCode(abilCaptionBar, 3, function mouseLeaveCaption, false)

        set abilCloseBtn = GUICreateButton(abilRoot)
        call GUISetPoint(abilCloseBtn, abilRoot, R2I(ABIL_W) - 40, 8)
        call GUISetSize(abilCloseBtn, 32, 32)
        call DzFrameSetScriptByCode(abilCloseBtn, 1, function onCloseClick, false)
        set bg = GUICreateImage(abilCloseBtn)
        call GUISetPoint(bg, abilCloseBtn, 0, 0)
        call GUISetSize(bg, 32, 32)
        call GUISetImage(bg, "UI_icon_close.tga")

        // 프리셋 탭 3개 (가로, 타이틀 아래) — 활성 프리셋 강조, 클릭 시 전환(sync)
        set i = 0
        loop
            exitwhen i >= ABIL_PRESETS
            set abilPresetBtn[i] = GUICreateButton(abilRoot)
            call GUISetPoint(abilPresetBtn[i], abilRoot, 18 + i * 138, 46)
            call GUISetSize(abilPresetBtn[i], 128, 26)
            set abilPresetBg[i] = GUICreateImage(abilPresetBtn[i])
            call GUISetPoint(abilPresetBg[i], abilPresetBtn[i], 0, 0)
            call GUISetSize(abilPresetBg[i], 128, 26)
            call GUISetImage(abilPresetBg[i], "UI_tab_btn.tga")
            call GUISetAlpha(abilPresetBg[i], 140)
            set abilPresetUnder[i] = GUICreateImage(abilPresetBtn[i])
            call GUISetPoint(abilPresetUnder[i], abilPresetBtn[i], 0, 18)
            call GUISetSize(abilPresetUnder[i], 128, 8)
            call GUISetImage(abilPresetUnder[i], "UI_tab_underline.tga")
            call GUIShow(abilPresetUnder[i], false)
            set abilPresetText[i] = GUICreateText(abilPresetBtn[i])
            call GUISetPointEx(abilPresetText[i], GUI_DOCK_MIDDLECENTER, abilPresetBtn[i], GUI_DOCK_MIDDLECENTER, 0, 0)
            call GUISetFont(abilPresetText[i], MAP_FONT_BOLD, 12)
            call GUISetText(abilPresetText[i], "프리셋 " + I2S(i + 1))
            set i = i + 1
        endloop
        call DzFrameSetScriptByCode(abilPresetBtn[0], 1, function onPreset0, false)
        call DzFrameSetScriptByCode(abilPresetBtn[1], 1, function onPreset1, false)
        call DzFrameSetScriptByCode(abilPresetBtn[2], 1, function onPreset2, false)

        set abilHeadText = GUICreateText(abilRoot)
        call GUISetPoint(abilHeadText, abilRoot, 20, 80)
        call GUISetFont(abilHeadText, MAP_FONT_BOLD, 14)

        // 프리셋 적용 버튼 (헤더 우측) — 보고 있는 프리셋을 능력치에 적용
        set abilApplyBtn = GUICreateButton(abilRoot)
        call GUISetPoint(abilApplyBtn, abilRoot, R2I(ABIL_W) - 130, 74)
        call GUISetSize(abilApplyBtn, 110, 28)
        call DzFrameSetScriptByCode(abilApplyBtn, 1, function onApplyClick, false)
        set abilApplyBg = GUICreateImage(abilApplyBtn)
        call GUISetPoint(abilApplyBg, abilApplyBtn, 0, 0)
        call GUISetSize(abilApplyBg, 110, 28)
        call GUISetImage(abilApplyBg, "UI_plate_none.tga")
        call GUISetAlpha(abilApplyBg, 90)
        set abilApplyText = GUICreateText(abilApplyBtn)
        call GUISetPointEx(abilApplyText, GUI_DOCK_MIDDLECENTER, abilApplyBtn, GUI_DOCK_MIDDLECENTER, 0, 0)
        call GUISetFont(abilApplyText, MAP_FONT_BOLD, 13)
        call GUISetText(abilApplyText, "|cff6f7890적용 중|r")

        // 5줄 옵션 + 줄 클릭(고정 토글) 버튼
        set line = 0
        loop
            exitwhen line >= ABIL_LINES
            set abilLineText[line] = GUICreateText(abilRoot)
            call GUISetPoint(abilLineText[line], abilRoot, 28, 112 + line * 44)
            call GUISetFont(abilLineText[line], MAP_FONT_BOLD, 16)

            set abilLineBtn[line] = GUICreateButton(abilRoot)
            call GUISetPoint(abilLineBtn[line], abilRoot, 22, 106 + line * 44)
            call GUISetSize(abilLineBtn[line], R2I(ABIL_W) - 44, 40)
            if line == 0 then
                call DzFrameSetScriptByCode(abilLineBtn[line], 1, function onLock0, false)
            elseif line == 1 then
                call DzFrameSetScriptByCode(abilLineBtn[line], 1, function onLock1, false)
            elseif line == 2 then
                call DzFrameSetScriptByCode(abilLineBtn[line], 1, function onLock2, false)
            elseif line == 3 then
                call DzFrameSetScriptByCode(abilLineBtn[line], 1, function onLock3, false)
            else
                call DzFrameSetScriptByCode(abilLineBtn[line], 1, function onLock4, false)
            endif
            set line = line + 1
        endloop

        // 잠금 안내 (좌측 패널 중앙 — abilRoot 는 확률/옵션 패널까지 포함한 전체 폭이라 MIDDLECENTER 쓰면 오른쪽으로 밀림)
        set abilLockText = GUICreateText(abilRoot)
        call GUISetPointEx(abilLockText, GUI_DOCK_MIDDLECENTER, abilRoot, GUI_DOCK_TOPLEFT, ABIL_W / 2.0, ABIL_H / 2.0)
        call GUISetFont(abilLockText, MAP_FONT_BOLD, 15)
        call GUIShow(abilLockText, false)

        set abilSilverText = GUICreateText(abilRoot)
        call GUISetPoint(abilSilverText, abilRoot, 20, 330)
        call GUISetFont(abilSilverText, MAP_FONT_BOLD, 13)

        // 재설정(1회) 버튼
        set abilRerollBtn = GUICreateButton(abilRoot)
        call GUISetPoint(abilRerollBtn, abilRoot, 20, 384)
        call GUISetSize(abilRerollBtn, 196, 42)
        call DzFrameSetScriptByCode(abilRerollBtn, 1, function onRerollClick, false)
        set bg = GUICreateImage(abilRerollBtn)
        call GUISetPoint(bg, abilRerollBtn, 0, 0)
        call GUISetSize(bg, 196, 42)
        call GUISetImage(bg, "UI_plate_none.tga")
        call GUISetAlpha(bg, 170)
        set abilRerollText = GUICreateText(abilRerollBtn)
        call GUISetPointEx(abilRerollText, GUI_DOCK_MIDDLECENTER, abilRerollBtn, GUI_DOCK_MIDDLECENTER, 0, 0)
        call GUISetFont(abilRerollText, MAP_FONT_BOLD, 15)
        call GUISetText(abilRerollText, "재설정")

        // 자동 재설정 버튼 (목표 등급까지 반복)
        set abilAutoBtn = GUICreateButton(abilRoot)
        call GUISetPoint(abilAutoBtn, abilRoot, 224, 384)
        call GUISetSize(abilAutoBtn, 196, 42)
        call DzFrameSetScriptByCode(abilAutoBtn, 1, function onAutoClick, false)
        set bg = GUICreateImage(abilAutoBtn)
        call GUISetPoint(bg, abilAutoBtn, 0, 0)
        call GUISetSize(bg, 196, 42)
        call GUISetImage(bg, "UI_plate_none.tga")
        call GUISetAlpha(bg, 170)
        set abilAutoText = GUICreateText(abilAutoBtn)
        call GUISetPointEx(abilAutoText, GUI_DOCK_MIDDLECENTER, abilAutoBtn, GUI_DOCK_MIDDLECENTER, 0, 0)
        call GUISetFont(abilAutoText, MAP_FONT_BOLD, 15)
        call GUISetText(abilAutoText, "|cff88FF88▶ 자동 재설정|r")

        // 가이드 설명
        set abilGuideText = GUICreateText(abilRoot)
        call GUISetPoint(abilGuideText, abilRoot, 22, 436)
        call GUISetFont(abilGuideText, MAP_FONT_LIGHT, 11)
        call GUISetText(abilGuideText, "|cffD8D0C0[등급]|r |cffBBBBBB노멀|r<|cff5599FF레어|r<|cffCC44FF에픽|r<|cffFFCC00유니크|r<|cff00DD66레전드리|r<|cffFF5544미스틱|r|n|cffBFD4E8· 1번째 줄 = 전체 등급, 2~5번째 줄 = 그 이하|r|n|cffBFD4E8· 재설정할수록 변환 레벨↑ → 상위 등급 확률↑|r|n|cffD4AF37· 줄 클릭 = 고정/해제 (고정 줄은 재설정 시 유지)|r|n|cff66FF66· 자동 재설정 = 목표 등급(+옵션 필터)까지 반복(실버 소진 시 정지)|r|n|cff66FF99· 프리셋 탭 = 보기/재설정, [적용하기] = 능력치에 적용 (◆ = 적용 중, 변환 레벨 공통)|r")

        set pid = 0
        loop
            exitwhen pid >= MAX_PLAYERS
            set abilTargetGrade[pid] = 3
            set abilOptMask[pid] = 0
            set pid = pid + 1
        endloop

        // ── 확률 가이드 패널 (우측, 변환 레벨별 등급 확률) ──
        set abilProbRoot = GUICreateContainer(abilRoot)
        call GUISetPoint(abilProbRoot, abilRoot, R2I(ABIL_W) + 10, 0)
        call GUISetSize(abilProbRoot, PROB_W, PROB_H)

        set bg = GUICreateImage(abilProbRoot)
        call GUISetPoint(bg, abilProbRoot, 0, 0)
        call GUISetSize(bg, PROB_W, PROB_H)
        call GUISetImage(bg, "UI_plate_none.tga")
        call GUISetAlpha(bg, 244)

        set abilProbTitle = GUICreateTextShadow(abilProbRoot)
        call GUISetPoint(abilProbTitle, abilProbRoot, 18, 14)
        call GUISetFont(abilProbTitle, MAP_FONT_BOLD, 16)
        call GUISetText(abilProbTitle, "|cffD4AF37등급 확률|r")

        set abilProbSub = GUICreateText(abilProbRoot)
        call GUISetPoint(abilProbSub, abilProbRoot, 18, 44)
        call GUISetFont(abilProbSub, MAP_FONT_BOLD, 12)

        set line = 0
        loop
            exitwhen line >= ABIL_GRADES
            set abilProbRow[line] = GUICreateText(abilProbRoot)
            call GUISetPoint(abilProbRow[line], abilProbRoot, 22, 78 + line * 32)
            call GUISetFont(abilProbRow[line], MAP_FONT_BOLD, 15)
            set line = line + 1
        endloop

        set abilProbNote = GUICreateText(abilProbRoot)
        call GUISetPoint(abilProbNote, abilProbRoot, 18, 280)
        call GUISetFont(abilProbNote, MAP_FONT_LIGHT, 11)
        call GUISetText(abilProbNote, "|cffBFD4E8재설정할수록 변환 레벨이 올라|n상위 등급 확률이 증가합니다.|n(확률 적용 상한 " + I2S(ABIL_CONV_CAP) + ")|r")

        // ── 목표 등급 선택 패널 (우측, 등급 확률 패널 바로 아래 상시 표시) ──
        set abilGradePanel = GUICreateContainer(abilRoot)
        call GUISetPoint(abilGradePanel, abilRoot, R2I(ABIL_W) + 10, R2I(PROB_H) + 10)
        call GUISetSize(abilGradePanel, PROB_W, 196.0)

        set bg = GUICreateImage(abilGradePanel)
        call GUISetPoint(bg, abilGradePanel, 0, 0)
        call GUISetSize(bg, PROB_W, 196.0)
        call GUISetImage(bg, "UI_plate_none.tga")
        call GUISetAlpha(bg, 244)

        set abilGradePanelTitle = GUICreateTextShadow(abilGradePanel)
        call GUISetPoint(abilGradePanelTitle, abilGradePanel, 18, 12)
        call GUISetFont(abilGradePanelTitle, MAP_FONT_BOLD, 15)
        call GUISetText(abilGradePanelTitle, "|cffD4AF37자동 목표 등급|r")

        set abilGradePanelSub = GUICreateText(abilGradePanel)
        call GUISetPoint(abilGradePanelSub, abilGradePanel, 18, 34)
        call GUISetFont(abilGradePanelSub, MAP_FONT_LIGHT, 11)
        call GUISetText(abilGradePanelSub, "|cffBFD4E8이 등급 이상이 나올 때까지 반복|r")

        set i = 1
        loop
            exitwhen i >= ABIL_GRADES
            set abilGradeRowBtn[i] = GUICreateButton(abilGradePanel)
            call GUISetPoint(abilGradeRowBtn[i], abilGradePanel, 12, 54 + (i - 1) * 27)
            call GUISetSize(abilGradeRowBtn[i], R2I(PROB_W) - 24, 25)
            set bg = GUICreateImage(abilGradeRowBtn[i])
            call GUISetPoint(bg, abilGradeRowBtn[i], 0, 0)
            call GUISetSize(bg, R2I(PROB_W) - 24, 25)
            call GUISetImage(bg, "UI_plate_none.tga")
            call GUISetAlpha(bg, 110)
            set abilGradeRowText[i] = GUICreateText(abilGradeRowBtn[i])
            call GUISetPoint(abilGradeRowText[i], abilGradeRowBtn[i], 10, 4)
            call GUISetFont(abilGradeRowText[i], MAP_FONT_BOLD, 14)
            if i == 1 then
                call DzFrameSetScriptByCode(abilGradeRowBtn[i], 1, function onPick1, false)
            elseif i == 2 then
                call DzFrameSetScriptByCode(abilGradeRowBtn[i], 1, function onPick2, false)
            elseif i == 3 then
                call DzFrameSetScriptByCode(abilGradeRowBtn[i], 1, function onPick3, false)
            elseif i == 4 then
                call DzFrameSetScriptByCode(abilGradeRowBtn[i], 1, function onPick4, false)
            else
                call DzFrameSetScriptByCode(abilGradeRowBtn[i], 1, function onPick5, false)
            endif
            set i = i + 1
        endloop
        call GUIShow(abilGradePanel, false)

        // ── 목표 옵션 필터 패널 (최우측, 다중선택 OR) ──
        set abilOptPanel = GUICreateContainer(abilRoot)
        call GUISetPoint(abilOptPanel, abilRoot, R2I(ABIL_W) + 10 + R2I(PROB_W) + 10, 0)
        call GUISetSize(abilOptPanel, OPT_W, 548.0)

        set bg = GUICreateImage(abilOptPanel)
        call GUISetPoint(bg, abilOptPanel, 0, 0)
        call GUISetSize(bg, OPT_W, 548.0)
        call GUISetImage(bg, "UI_plate_none.tga")
        call GUISetAlpha(bg, 244)

        set abilOptPanelTitle = GUICreateTextShadow(abilOptPanel)
        call GUISetPoint(abilOptPanelTitle, abilOptPanel, 16, 12)
        call GUISetFont(abilOptPanelTitle, MAP_FONT_BOLD, 15)
        call GUISetText(abilOptPanelTitle, "|cffD4AF37자동 목표 옵션|r")

        set abilOptPanelSub = GUICreateText(abilOptPanel)
        call GUISetPoint(abilOptPanelSub, abilOptPanel, 16, 33)
        call GUISetFont(abilOptPanelSub, MAP_FONT_LIGHT, 11)
        call GUISetText(abilOptPanelSub, "|cffBFD4E8선택 옵션 중 하나가|n목표 등급↑로 나오면 정지|n(다중 선택 가능)|r")

        // 전체(아무 옵션) 토글
        set abilOptAllBtn = GUICreateButton(abilOptPanel)
        call GUISetPoint(abilOptAllBtn, abilOptPanel, 12, 84)
        call GUISetSize(abilOptAllBtn, R2I(OPT_W) - 24, 26)
        set bg = GUICreateImage(abilOptAllBtn)
        call GUISetPoint(bg, abilOptAllBtn, 0, 0)
        call GUISetSize(bg, R2I(OPT_W) - 24, 26)
        call GUISetImage(bg, "UI_plate_none.tga")
        call GUISetAlpha(bg, 110)
        set abilOptAllText = GUICreateText(abilOptAllBtn)
        call GUISetPoint(abilOptAllText, abilOptAllBtn, 8, 5)
        call GUISetFont(abilOptAllText, MAP_FONT_BOLD, 12)
        call DzFrameSetScriptByCode(abilOptAllBtn, 1, function onOptAll, false)

        // 옵션 13종 행
        set i = 0
        loop
            exitwhen i >= OPT_COUNT
            set abilOptRowBtn[i] = GUICreateButton(abilOptPanel)
            call GUISetPoint(abilOptRowBtn[i], abilOptPanel, 12, 84 + (i + 1) * 29)
            call GUISetSize(abilOptRowBtn[i], R2I(OPT_W) - 24, 26)
            set bg = GUICreateImage(abilOptRowBtn[i])
            call GUISetPoint(bg, abilOptRowBtn[i], 0, 0)
            call GUISetSize(bg, R2I(OPT_W) - 24, 26)
            call GUISetImage(bg, "UI_plate_none.tga")
            call GUISetAlpha(bg, 110)
            set abilOptRowText[i] = GUICreateText(abilOptRowBtn[i])
            call GUISetPoint(abilOptRowText[i], abilOptRowBtn[i], 8, 5)
            call GUISetFont(abilOptRowText[i], MAP_FONT_BOLD, 12)
            call bindOptRow(i)
            set i = i + 1
        endloop
        call GUIShow(abilOptPanel, false)
    endfunction

    private function onInit takes nothing returns nothing
        local trigger t

        set t = CreateTrigger()
        call TriggerRegisterTimerEvent(t, 0.55, false)
        call TriggerAddAction(t, function onMapLoad)

        set t = CreateTrigger()
        call TriggerRegisterTimerEvent(t, 0.25, true)
        call TriggerAddAction(t, function update)

        // 자동 재설정 구동 (소유 클라에서만 sync 전송)
        set t = CreateTrigger()
        call TriggerRegisterTimerEvent(t, 0.12, true)
        call TriggerAddAction(t, function autoTick)

        set t = CreateTrigger()
        call DzTriggerRegisterSyncData(t, SYNC_CMD_REROLL, false)
        call TriggerAddAction(t, function onSyncReroll)

        set t = CreateTrigger()
        call DzTriggerRegisterSyncData(t, SYNC_CMD_PRESET, false)
        call TriggerAddAction(t, function onSyncPreset)

        set t = CreateTrigger()
        call DzTriggerRegisterSyncData(t, SYNC_CMD_VIEW, false)
        call TriggerAddAction(t, function onSyncView)

        // 창 드래그 (마우스 좌클릭 다운/업)
        set t = CreateTrigger()
        call DzTriggerRegisterMouseEventByCode(t, 0x1, 1, false, function onLMBDown)
        set t = CreateTrigger()
        call DzTriggerRegisterMouseEventByCode(t, 0x1, 0, false, function onLMBUp)

        set t = null
    endfunction

endscope
