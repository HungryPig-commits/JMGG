// ============================================================
// 미소녀 키우기 - 스킬 강화 UI
// ============================================================
// 본인 직업의 스킬 3개를 카드로 표시.
//   아이콘 / 이름 / 레벨 / 현재효과 / 다음효과 / 강화비용 / 강화버튼
// 강화: DzSyncData → 실버 차감 + SkillUpgrade + RecalcStats
// 캡션바 드래그로 이동.
// ============================================================

scope UISkill initializer onInit

    static if not REFORGED_MODE then
    native DzSyncData takes string prefix, string data returns nothing
    native DzGetTriggerUIEventFrame takes nothing returns integer
    native DzGetTriggerUIEventPlayer takes nothing returns player
    native DzFrameSetScriptByCode takes integer frame, integer eventId, code funcHandle, boolean sync returns nothing
    native DzGetTriggerSyncPlayer takes nothing returns player
    native DzGetTriggerSyncData takes nothing returns string
    native DzTriggerRegisterSyncData takes trigger t, string prefix, boolean server returns nothing
    native DzTriggerRegisterMouseEventByCode takes trigger trig, integer btn, integer status, boolean sync, code funcHandle returns nothing
    native DzGetMouseXRelative takes nothing returns integer
    native DzGetMouseYRelative takes nothing returns integer
    endif

    globals
        private constant string SYNC_SKILLUP = "SKSKILLUP"
        private constant string SYNC_AUX_EQ = "SKAUXEQ"      /* 보조스킬 장착 (data=ridx) */
        private constant string SYNC_AUX_UNEQ = "SKAUXUEQ"   /* 보조스킬 해제 (data=slot) */
        private constant real SK_W = 880.0       /* 전체 창 폭 (좌:카드 / 우:보조스킬) */
        private constant real CARD_W = 512.0     /* 좌측 카드 컬럼 폭 */
        private constant real AUXX = 530.0       /* 우측 보조스킬 패널 시작 x */
        private constant real SK_H = 690.0
        private constant integer SK_CARDS = 4    /* 동시 표시 카드 칸 수(스크롤 창 크기) */
        private constant integer AUX_ROWS = 6    /* 보유 보조스킬 동시 표시 행 수(스크롤 창 크기) */
        private constant integer AUX_ROW_Y = 310 /* 보유 목록 시작 Y (휠영역/스크롤바 기준) */
        private constant integer AUX_ROW_H = 58  /* 보유 목록 행 1칸 높이=간격 */
        private constant real SK_ROW_Y = 54.0    /* 카드 시작 Y (스크롤바/휠영역 기준) */
        private constant real SK_ROW_H = 150.0   /* 카드 1장 높이=간격 */

        private integer skLayer = 0
        private integer skRoot = 0
        private integer skBackdrop = 0
        private integer skCaption = 0
        private integer skTitle = 0
        private integer skCloseBtn = 0
        private integer skSilverText = 0

        private integer array cardBg
        private integer array cardIcon
        private integer array cardName
        private integer array cardLv
        private integer array cardEff
        private integer array cardNext
        private integer array cardCost
        private integer array cardBtn
        private integer array cardHover

        // 카드 스크롤 (스킬 슬롯 SKILL_SLOTS개 > 카드칸 SK_CARDS개)
        private integer array skillScroll    /* [pid] 카드 스크롤 오프셋 */
        private integer skWheelArea = 0
        private integer skScrollTrack = 0
        private integer skScrollThumb = 0

        // 보조 스킬 패널 (우측)
        private integer auxTitle = 0
        private integer auxSlotLabel = 0
        private integer array auxSlotBg
        private integer array auxSlotIcon
        private integer array auxSlotText
        private integer array auxSlotBtn
        private integer auxOwnedLabel = 0
        private integer array auxRowBg
        private integer array auxRowIcon
        private integer array auxRowText
        private integer array auxRowBtn

        // 보유 보조스킬 스크롤 (보조스킬 종류 > 행 칸 AUX_ROWS 개)
        private integer array auxScroll      /* [pid] 보유 목록 스크롤 오프셋 */
        private integer auxWheelArea = 0
        private integer auxScrollTrack = 0
        private integer auxScrollThumb = 0

        boolean array skillVisible
        private integer skX = 200
        private integer skY = 18

        private string hovering = null
        private string dragging = null

        private hashtable memHash = InitHashtable()

        // 동적 스킬 툴팁 (마우스 추종)
        private constant real TIP_W = 350.0
        private constant real TIP_H = 330.0
        private integer skTipRoot = 0
        private integer skTipBg = 0
        private integer skTipTitle = 0
        private integer skTipBody = 0
        private integer hoverSlot = -1
    endglobals

    // ============================================================
    // 갱신
    // ============================================================

    // cardIdx = 카드 프레임 칸(0..SK_CARDS-1), slot = 실제 스킬 슬롯(스크롤 오프셋 반영)
    private function renderCard takes integer pid, integer job, integer cardIdx, integer slot returns nothing
        local integer lv = SkillGetLevel(pid, slot)
        local integer cost

        // 클릭/hover 가 실제 슬롯을 가리키도록 매 render 매핑 갱신 (스크롤로 칸↔슬롯이 바뀜)
        call SaveInteger(memHash, cardBtn[cardIdx], 0, slot)
        call SaveInteger(memHash, cardHover[cardIdx], 0, slot)

        call GUISetText(cardName[cardIdx], "|cffd4af37" + SkillNameFor(pid, slot) + "|r")
        call GUISetImage(cardIcon[cardIdx], SkillIconFor(pid, slot))

        // 필살기 (slot4): 레벨/강화 없는 고정 효과 — 다른 스킬과 동일 패턴으로 표기
        if slot == SKILL_FINISHER_SLOT then
            call GUIShow(cardBtn[cardIdx], false)
            if not SkillIsLearned(pid, slot) then
                call GUISetAlpha(cardIcon[cardIdx], 90)
                call GUISetText(cardLv[cardIdx], "|cffFF8866미습득|r")
                call GUISetText(cardEff[cardIdx], "|cffFFCC88Lv." + I2S(SkillLearnLevel(slot)) + " 달성 시 자동 습득|r")
                call GUISetText(cardNext[cardIdx], "|cff8FA8C8예상 효과: " + SkillEffectShortFor(pid, slot, 1) + "|r")
                call GUISetText(cardCost[cardIdx], "")
            else
                call GUISetAlpha(cardIcon[cardIdx], 255)
                call GUISetText(cardLv[cardIdx], "|cff44FF44습득 완료|r")
                call GUISetText(cardEff[cardIdx], "|cffEAEAEA" + SkillEffectShortFor(pid, slot, 1) + "|r")
                call GUISetText(cardNext[cardIdx], "")
                call GUISetText(cardCost[cardIdx], "")
            endif
            return
        endif

        // 공용 마스터 패시브 (slot3): 강화 없음 — 고정 효과만 표기
        if slot == SKILL_PASSIVE_SLOT then
            call GUIShow(cardBtn[cardIdx], false)
            if not SkillIsLearned(pid, slot) then
                call GUISetAlpha(cardIcon[cardIdx], 90)
                call GUISetText(cardLv[cardIdx], "|cffFF66CC[공용 마스터]|r")
                call GUISetText(cardEff[cardIdx], "|cffFFCC88Lv." + I2S(SkillLearnLevel(slot)) + " 달성 시 자동 습득|r")
                call GUISetText(cardNext[cardIdx], "|cff8FA8C8효과: " + SkillEffectShortFor(pid, slot, 1) + "|r")
                call GUISetText(cardCost[cardIdx], "")
            else
                call GUISetAlpha(cardIcon[cardIdx], 255)
                call GUISetText(cardLv[cardIdx], "|cffFF66CC[공용 마스터]|r")
                call GUISetText(cardEff[cardIdx], "|cffEAEAEA" + SkillEffectShortFor(pid, slot, lv) + "|r")
                call GUISetText(cardNext[cardIdx], "")
                call GUISetText(cardCost[cardIdx], "|cff44FF44습득 완료|r")
            endif
            return
        endif

        if not SkillIsLearned(pid, slot) then
            call GUISetAlpha(cardIcon[cardIdx], 90)
            call GUISetText(cardLv[cardIdx], "|cffFF8866미습득|r")
            call GUISetText(cardEff[cardIdx], "|cffFFCC88Lv." + I2S(SkillLearnLevel(slot)) + " 달성 시 자동 습득|r")
            call GUISetText(cardNext[cardIdx], "|cff8FA8C8예상 효과: " + SkillEffectShortFor(pid, slot, 1) + "|r")
            call GUISetText(cardCost[cardIdx], "")
            call GUIShow(cardBtn[cardIdx], false)
            return
        endif

        call GUISetAlpha(cardIcon[cardIdx], 255)
        call GUISetText(cardEff[cardIdx], "|cffEAEAEA" + SkillEffectShortFor(pid, slot, lv) + "|r")

        if lv >= SKILL_MAX_LEVEL then
            call GUISetText(cardLv[cardIdx], "|cff44FF44Lv. " + I2S(lv) + "  (MAX)|r")
            call GUISetText(cardNext[cardIdx], "")
            call GUISetText(cardCost[cardIdx], "|cff44FF44최대 레벨 달성|r")
            call GUIShow(cardBtn[cardIdx], false)
            return
        endif

        set cost = SkillUpgradeCost(slot, lv)
        call GUISetText(cardLv[cardIdx], "|cffd8d0c0Lv. " + I2S(lv) + " |r|cff8FA8C8/ " + I2S(SKILL_MAX_LEVEL) + "|r")
        call GUISetText(cardNext[cardIdx], "|cff66CCFF▶ 다음 Lv." + I2S(lv + 1) + ":  " + SkillEffectShortFor(pid, slot, lv + 1) + "|r")
        call GUISetText(cardCost[cardIdx], "|cffC8D2DC강화 비용|r|n|cffd4af37" + I2S(cost) + " 실버|r")
        call GUIShow(cardBtn[cardIdx], true)
    endfunction

    // 보유 보조스킬 개수 (스크롤 범위 계산 — render/휠 공용)
    private function auxOwnedCount takes integer pid returns integer
        local integer i = 0
        local integer n = 0
        loop
            exitwhen i >= AuxCount()
            if AuxOwns(pid, i) then
                set n = n + 1
            endif
            set i = i + 1
        endloop
        return n
    endfunction

    // 보조 스킬 패널 갱신 (장착 슬롯 + 보유 목록)
    //   보유 목록은 AUX_ROWS 칸짜리 스크롤 창이다. 보유 종류가 칸 수를 넘으면 휠로 넘긴다.
    //   (2026-09-20: 보조스킬이 9종이 되면서 7번째부터 영영 안 보이던 것을 고침)
    private function renderAuxPanel takes integer pid returns nothing
        local integer slot = 0
        local integer i = 0
        local integer row = 0
        local integer ridx
        local integer owned
        local integer seen = 0
        local integer maxOff
        local integer off
        local real trackH
        local real thumbH
        local real thumbY
        local string eqMark

        loop
            exitwhen slot >= AUX_SLOTS
            set ridx = AuxEquippedAt(pid, slot)
            if ridx >= 0 then
                call GUISetImage(auxSlotIcon[slot], AuxIcon(ridx))
                call GUISetAlpha(auxSlotIcon[slot], 255)
                call GUISetText(auxSlotText[slot], "|cffd8d0c0" + AuxName(ridx) + "|r |cff8FA8C8Lv." + I2S(AuxLv(pid, ridx)) + "|r|n|cffAEB9C6좌클릭 해제|r")
            else
                call GUISetImage(auxSlotIcon[slot], "UI_Slot_Basic.tga")
                call GUISetAlpha(auxSlotIcon[slot], 110)
                call GUISetText(auxSlotText[slot], "|cff5a564c(비어 있음)|r")
            endif
            set slot = slot + 1
        endloop

        // 스크롤 오프셋 보정 (표시 전용 — 전역 변경은 onAuxWheel 에서)
        set owned = auxOwnedCount(pid)
        set maxOff = owned - AUX_ROWS
        if maxOff < 0 then
            set maxOff = 0
        endif
        set off = auxScroll[pid]
        if off > maxOff then
            set off = maxOff
        endif
        if off < 0 then
            set off = 0
        endif

        loop
            exitwhen i >= AuxCount()
            if AuxOwns(pid, i) then
                if seen >= off and row < AUX_ROWS then
                    set eqMark = ""
                    if AuxIsEquipped(pid, i) then
                        set eqMark = "|cff44FF44[장착중] |r"
                    endif
                    call GUIShow(auxRowBg[row], true)
                    call GUIShow(auxRowIcon[row], true)
                    call GUIShow(auxRowText[row], true)
                    call GUIShow(auxRowBtn[row], true)
                    call GUISetImage(auxRowIcon[row], AuxIcon(i))
                    call GUISetText(auxRowText[row], eqMark + "|cffd4af37" + AuxName(i) + "|r |cff8FA8C8Lv." + I2S(AuxLv(pid, i)) + "|r|n|cffBBBBBB" + AuxEffectText(i, AuxLv(pid, i)) + "|r")
                    call SaveInteger(memHash, auxRowBtn[row], 0, i)
                    set row = row + 1
                endif
                set seen = seen + 1
            endif
            set i = i + 1
        endloop
        loop
            exitwhen row >= AUX_ROWS
            call GUIShow(auxRowBg[row], false)
            call GUIShow(auxRowIcon[row], false)
            call GUIShow(auxRowText[row], false)
            call GUIShow(auxRowBtn[row], false)
            set row = row + 1
        endloop

        // 스크롤 위치바 (휠로만 스크롤, thumb 은 현재 위치 표시)
        if maxOff <= 0 then
            call GUIShow(auxScrollTrack, false)
            call GUIShow(auxScrollThumb, false)
        else
            call GUIShow(auxScrollTrack, true)
            call GUIShow(auxScrollThumb, true)
            set trackH = I2R(AUX_ROW_H * AUX_ROWS)
            set thumbH = trackH * I2R(AUX_ROWS) / I2R(owned)
            if thumbH < 24.0 then
                set thumbH = 24.0
            endif
            set thumbY = I2R(AUX_ROW_Y) + (trackH - thumbH) * I2R(off) / I2R(maxOff)
            call GUIClearAllPoints(auxScrollThumb)
            call GUISetPoint(auxScrollThumb, skRoot, R2I(AUXX) + 306, R2I(thumbY))
            call GUISetSize(auxScrollThumb, 10, thumbH)
        endif
    endfunction

    private function update takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer job
        local integer slot
        local integer maxOff
        local integer off
        local real trackH
        local real thumbH
        local real thumbY

        if not skillVisible[pid] then
            return
        endif

        set job = player_job[pid]
        call GUISetText(skSilverText, "|cffC8D2DC보유 실버:|r |cffd4af37" + SilverFmt(pid) + "|r")

        // 스크롤 오프셋 보정 (표시 전용 — 전역 변경은 onWheel 에서)
        set maxOff = SKILL_SLOTS - SK_CARDS
        if maxOff < 0 then
            set maxOff = 0
        endif
        set off = skillScroll[pid]
        if off > maxOff then
            set off = maxOff
        endif
        if off < 0 then
            set off = 0
        endif

        set slot = 0
        loop
            exitwhen slot >= SK_CARDS
            call renderCard(pid, job, slot, off + slot)
            set slot = slot + 1
        endloop

        // 스크롤 위치바 (휠로 스크롤, thumb 은 현재 위치 표시)
        if maxOff <= 0 then
            call GUIShow(skScrollThumb, false)
        else
            call GUIShow(skScrollThumb, true)
            set trackH = SK_ROW_H * I2R(SK_CARDS)
            set thumbH = trackH * I2R(SK_CARDS) / I2R(SKILL_SLOTS)
            if thumbH < 24.0 then
                set thumbH = 24.0
            endif
            set thumbY = SK_ROW_Y + (trackH - thumbH) * I2R(off) / I2R(maxOff)
            call GUIClearAllPoints(skScrollThumb)
            call GUISetPoint(skScrollThumb, skRoot, R2I(CARD_W) - 12, R2I(thumbY))
            call GUISetSize(skScrollThumb, 10, thumbH)
        endif

        call renderAuxPanel(pid)

        // 마우스가 카드 위에 있으면 동적 툴팁 표시 (hoverSlot = 실제 스킬 슬롯)
        if skTipRoot != 0 then
            if hoverSlot >= 0 and hoverSlot < SKILL_SLOTS then
                call GUISetText(skTipTitle, SkillTipTitle(pid, hoverSlot))
                call GUISetText(skTipBody, SkillTipBody(pid, hoverSlot))
                call GUIShow(skTipRoot, true)
            else
                call GUIShow(skTipRoot, false)
            endif
        endif
    endfunction

    // 카드 휠 스크롤 (휠 위로=오프셋 감소). thumb 표시는 update 가 담당.
    private function onWheel takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer maxOff
        local integer next

        if not skillVisible[pid] then
            return
        endif

        set maxOff = SKILL_SLOTS - SK_CARDS
        if maxOff < 0 then
            set maxOff = 0
        endif

        set next = skillScroll[pid]
        if DzGetWheelDelta() > 0 then
            set next = next - 1
        else
            set next = next + 1
        endif
        if next < 0 then
            set next = 0
        endif
        if next > maxOff then
            set next = maxOff
        endif

        // 변화 없으면 재그리기 생략 (튐 방지)
        if next == skillScroll[pid] then
            return
        endif
        set skillScroll[pid] = next
        call update()
    endfunction

    // 보유 보조스킬 목록 휠 스크롤. thumb 표시는 renderAuxPanel 이 담당.
    private function onAuxWheel takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer maxOff
        local integer next

        if not skillVisible[pid] then
            return
        endif

        set maxOff = auxOwnedCount(pid) - AUX_ROWS
        if maxOff < 0 then
            set maxOff = 0
        endif

        set next = auxScroll[pid]
        if DzGetWheelDelta() > 0 then
            set next = next - 1
        else
            set next = next + 1
        endif
        if next < 0 then
            set next = 0
        endif
        if next > maxOff then
            set next = maxOff
        endif

        if next == auxScroll[pid] then
            return
        endif
        set auxScroll[pid] = next
        call update()
    endfunction

    function ToggleSkillUI takes integer pid returns nothing
        set skillVisible[pid] = not skillVisible[pid]
        if GetLocalPlayer() == Player(pid) then
            if not skillVisible[pid] then
                set hoverSlot = -1
                call GUIShow(skTipRoot, false)
            endif
            call GUIShow(skLayer, skillVisible[pid])
        endif
        call update()
    endfunction

    // ESC 등으로 닫기 (열려있을 때만)
    function CloseSkillUI takes integer pid returns nothing
        if skillVisible[pid] then
            set skillVisible[pid] = false
            if GetLocalPlayer() == Player(pid) then
                set hoverSlot = -1
                call GUIShow(skTipRoot, false)
                call GUIShow(skLayer, false)
            endif
        endif
    endfunction

    // ============================================================
    // 입력
    // ============================================================

    private function onClose takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        call SfxClick(pid)
        set skillVisible[pid] = false
        set hoverSlot = -1
        call GUIShow(skTipRoot, false)
        call GUIShow(skLayer, false)
    endfunction

    // 카드 hover → 동적 툴팁 표시 (slot은 memHash에 저장됨)
    private function onCardEnter takes nothing returns nothing
        set hoverSlot = LoadInteger(memHash, DzGetTriggerUIEventFrame(), 0)
    endfunction
    private function onCardLeave takes nothing returns nothing
        set hoverSlot = -1
    endfunction

    private function onUpClick takes nothing returns nothing
        local integer pid = GetPlayerId(GetLocalPlayer())
        local integer slot = LoadInteger(memHash, DzGetTriggerUIEventFrame(), 0)
        call SfxClick(pid)
        if not SkillIsLearned(pid, slot) then
            return
        endif
        if SkillGetLevel(pid, slot) >= SKILL_MAX_LEVEL then
            return
        endif
        call DzSyncData(SYNC_SKILLUP, I2S(slot))
    endfunction

    // 보조스킬 장착 슬롯 클릭 → 해제
    private function onAuxSlotClick takes nothing returns nothing
        call SfxClick(GetPlayerId(GetLocalPlayer()))
        call DzSyncData(SYNC_AUX_UNEQ, I2S(LoadInteger(memHash, DzGetTriggerUIEventFrame(), 0)))
    endfunction

    // 보유 보조스킬 [장착] 클릭 → 빈 슬롯 장착
    private function onAuxRowClick takes nothing returns nothing
        call SfxClick(GetPlayerId(GetLocalPlayer()))
        call DzSyncData(SYNC_AUX_EQ, I2S(LoadInteger(memHash, DzGetTriggerUIEventFrame(), 0)))
    endfunction

    private function onCapEnter takes nothing returns nothing
        set hovering = "cap"
        call SfxHover(GetPlayerId(GetLocalPlayer()))
    endfunction
    private function onCapLeave takes nothing returns nothing
        if hovering == "cap" then
            set hovering = null
        endif
    endfunction

    private function startDrag takes nothing returns nothing
        local real cursorX = 1.0 * DzGetMouseXRelative() / gx_localScreenWidth * GUIGetScreenWidth()
        local real cursorY = 1.0 * DzGetMouseYRelative() / gx_localScreenHeight * GUIGetScreenHeight()
        set dragging = "cap"
        set gx_cursorOffsetX = -0.8 * (cursorX - skX) / GUIGetScreenWidth()
        set gx_cursorOffsetY = 0.6 * (cursorY - skY) / GUIGetScreenHeight()
        call GUIClearAllPoints(skRoot)
        call GUISetPoint(skRoot, gx_cursorFrame, 0, 0)
    endfunction

    private function stopDrag takes nothing returns nothing
        local real offsetX = gx_cursorOffsetX / 0.8 * GUIGetScreenWidth()
        local real offsetY = gx_cursorOffsetY / -0.6 * GUIGetScreenHeight()
        local real cursorX = 1.0 * DzGetMouseXRelative() / gx_localScreenWidth * GUIGetScreenWidth()
        local real cursorY = 1.0 * DzGetMouseYRelative() / gx_localScreenHeight * GUIGetScreenHeight()
        set dragging = null
        set skX = R2I(cursorX + offsetX)
        set skY = R2I(cursorY + offsetY)
        call GUIClearAllPoints(skRoot)
        call GUISetPoint(skRoot, skLayer, skX, skY)
    endfunction

    private function onLMBDown takes nothing returns nothing
        if dragging == null and hovering == "cap" then
            call startDrag()
        endif
    endfunction
    private function onLMBUp takes nothing returns nothing
        if dragging == "cap" then
            call stopDrag()
        endif
    endfunction

    // ============================================================
    // 동기화
    // ============================================================

    private function onSyncUp takes nothing returns nothing
        local integer pid = GetPlayerId(DzGetTriggerSyncPlayer())
        local integer slot = S2I(DzGetTriggerSyncData())
        local integer lv
        local integer cost

        // 강화 불가 슬롯(공용 패시브/필살기)은 서버측에서도 차단 — 버튼 숨김 외 이중 방어
        if slot == SKILL_PASSIVE_SLOT or slot == SKILL_FINISHER_SLOT then
            return
        endif
        if not SkillIsLearned(pid, slot) then
            return
        endif
        set lv = SkillGetLevel(pid, slot)
        if lv >= SKILL_MAX_LEVEL then
            return
        endif
        set cost = SkillUpgradeCost(slot, lv)
        if not SilverSpend(pid, cost) then
            call MsgError(Player(pid), "실버가 부족합니다. (필요: " + I2S(cost) + ")")
            return
        endif
        call SkillUpgrade(pid, slot)
        call RecalcStats(pid)
        // 커맨드카드 표시 어빌리티 툴팁을 현재 레벨로 갱신(로컬)
        call SkillApplyHeroAbilities(pid)
        call MsgSuccess(Player(pid), SkillNameFor(pid, slot) + " Lv." + I2S(SkillGetLevel(pid, slot)) + " 강화 성공!")
    endfunction

    // 보조스킬 장착 (빈 슬롯)
    private function onSyncAuxEq takes nothing returns nothing
        local integer pid = GetPlayerId(DzGetTriggerSyncPlayer())
        local integer ridx = S2I(DzGetTriggerSyncData())
        if not AuxOwns(pid, ridx) or AuxIsEquipped(pid, ridx) then
            return
        endif
        if AuxEquipFirstFree(pid, ridx) then
            call RecalcStats(pid)
            call AuxApplyHeroAbilities(pid)
            call MsgSuccess(Player(pid), AuxName(ridx) + " 장착!")
        else
            call MsgError(Player(pid), "장착 슬롯이 가득 찼습니다. (슬롯을 좌클릭해 해제하세요)")
        endif
        call update()
    endfunction

    // 보조스킬 해제 (슬롯)
    private function onSyncAuxUneq takes nothing returns nothing
        local integer pid = GetPlayerId(DzGetTriggerSyncPlayer())
        local integer slot = S2I(DzGetTriggerSyncData())
        if AuxUnequip(pid, slot) then
            call RecalcStats(pid)
            call AuxApplyHeroAbilities(pid)
            call update()
        endif
    endfunction

    // ============================================================
    // UI 생성
    // ============================================================

    private function createCard takes integer slot, integer cy returns nothing
        local integer bg
        local integer lbl

        set cardBg[slot] = GUICreateImage(skRoot)
        call GUISetPoint(cardBg[slot], skRoot, 14, cy)
        call GUISetSize(cardBg[slot], CARD_W - 28.0, 150)
        call GUISetImage(cardBg[slot], "UI_plate_none.tga")
        call GUISetAlpha(cardBg[slot], 150)

        // 카드 전체 hover 영역 (강화 버튼보다 먼저 생성 → 버튼이 위에 옴)
        set cardHover[slot] = GUICreateButton(skRoot)
        call GUISetPoint(cardHover[slot], skRoot, 14, cy)
        call GUISetSize(cardHover[slot], CARD_W - 28.0, 150)
        call DzFrameSetScriptByCode(cardHover[slot], 2, function onCardEnter, false)
        call DzFrameSetScriptByCode(cardHover[slot], 3, function onCardLeave, false)
        call DzFrameSetScriptByCode(cardHover[slot], 6, function onWheel, false)
        call SaveInteger(memHash, cardHover[slot], 0, slot)

        set cardIcon[slot] = GUICreateImage(skRoot)
        call GUISetPoint(cardIcon[slot], skRoot, 28, cy + 16)
        call GUISetSize(cardIcon[slot], 64, 64)

        set cardName[slot] = GUICreateText(skRoot)
        call GUISetPoint(cardName[slot], skRoot, 104, cy + 14)
        call GUISetFont(cardName[slot], MAP_FONT_BOLD, 17)

        set cardLv[slot] = GUICreateText(skRoot)
        call GUISetPoint(cardLv[slot], skRoot, 104, cy + 42)
        call GUISetFont(cardLv[slot], MAP_FONT_BOLD, 13)

        set cardEff[slot] = GUICreateText(skRoot)
        call GUISetPoint(cardEff[slot], skRoot, 28, cy + 92)
        call GUISetFont(cardEff[slot], MAP_FONT_LIGHT, 13)

        set cardNext[slot] = GUICreateText(skRoot)
        call GUISetPoint(cardNext[slot], skRoot, 28, cy + 116)
        call GUISetFont(cardNext[slot], MAP_FONT_LIGHT, 12)

        set cardCost[slot] = GUICreateText(skRoot)
        call GUISetPoint(cardCost[slot], skRoot, R2I(CARD_W) - 200, cy + 14)
        call GUISetFont(cardCost[slot], MAP_FONT_BOLD, 12)

        set bg = GUICreateImage(skRoot)
        call GUISetPoint(bg, skRoot, R2I(CARD_W) - 156, cy + 54)
        call GUISetSize(bg, 130, 40)
        call GUISetImage(bg, "UI_plate_none.tga")
        call GUISetAlpha(bg, 220)

        set cardBtn[slot] = GUICreateButton(skRoot)
        call GUISetPoint(cardBtn[slot], skRoot, R2I(CARD_W) - 156, cy + 54)
        call GUISetSize(cardBtn[slot], 130, 40)
        call DzFrameSetScriptByCode(cardBtn[slot], 1, function onUpClick, false)
        call DzFrameSetScriptByCode(cardBtn[slot], 2, function onCardEnter, false)
        call DzFrameSetScriptByCode(cardBtn[slot], 3, function onCardLeave, false)
        call DzFrameSetScriptByCode(cardBtn[slot], 6, function onWheel, false)
        call SaveInteger(memHash, cardBtn[slot], 0, slot)

        set lbl = GUICreateText(cardBtn[slot])
        call GUISetPointEx(lbl, GUI_DOCK_MIDDLECENTER, cardBtn[slot], GUI_DOCK_MIDDLECENTER, 0, 0)
        call GUISetFont(lbl, MAP_FONT_BOLD, 15)
        call GUISetText(lbl, "|cffd4af37강  화|r")
    endfunction

    // 보조 스킬 패널 생성 (우측)
    private function createAuxPanel takes nothing returns nothing
        local integer slot = 0
        local integer row = 0
        local integer lbl
        local integer cy

        set auxTitle = GUICreateText(skRoot)
        call GUISetPoint(auxTitle, skRoot, R2I(AUXX), 50)
        call GUISetFont(auxTitle, MAP_FONT_BOLD, 18)
        call GUISetText(auxTitle, "|cffFF66CC보조 스킬|r")

        set auxSlotLabel = GUICreateText(skRoot)
        call GUISetPoint(auxSlotLabel, skRoot, R2I(AUXX), 82)
        call GUISetFont(auxSlotLabel, MAP_FONT_LIGHT, 12)
        call GUISetText(auxSlotLabel, "|cff8FA8C8장착 슬롯 (좌클릭 해제)|r")

        loop
            exitwhen slot >= AUX_SLOTS
            set cy = 104 + slot * 58
            set auxSlotBg[slot] = GUICreateImage(skRoot)
            call GUISetPoint(auxSlotBg[slot], skRoot, R2I(AUXX), cy)
            call GUISetSize(auxSlotBg[slot], 300, 52)
            call GUISetImage(auxSlotBg[slot], "UI_plate_none.tga")
            call GUISetAlpha(auxSlotBg[slot], 160)

            set auxSlotIcon[slot] = GUICreateImage(skRoot)
            call GUISetPoint(auxSlotIcon[slot], skRoot, R2I(AUXX) + 8, cy + 6)
            call GUISetSize(auxSlotIcon[slot], 40, 40)

            set auxSlotText[slot] = GUICreateText(skRoot)
            call GUISetPoint(auxSlotText[slot], skRoot, R2I(AUXX) + 56, cy + 8)
            call GUISetSize(auxSlotText[slot], 236, 44)
            call GUISetFont(auxSlotText[slot], MAP_FONT_LIGHT, 12)

            set auxSlotBtn[slot] = GUICreateButton(skRoot)
            call GUISetPoint(auxSlotBtn[slot], skRoot, R2I(AUXX), cy)
            call GUISetSize(auxSlotBtn[slot], 300, 52)
            call DzFrameSetScriptByCode(auxSlotBtn[slot], 1, function onAuxSlotClick, false)
            call SaveInteger(memHash, auxSlotBtn[slot], 0, slot)
            set slot = slot + 1
        endloop

        set auxOwnedLabel = GUICreateText(skRoot)
        call GUISetPoint(auxOwnedLabel, skRoot, R2I(AUXX), 288)
        call GUISetFont(auxOwnedLabel, MAP_FONT_LIGHT, 12)
        call GUISetText(auxOwnedLabel, "|cff8FA8C8보유 스킬 ([장착] 클릭 · 휠 스크롤)|r")

        // 보유 목록 휠 스크롤 영역 (MS_WheelArea 투명버튼 — 행보다 먼저 생성해 [장착] 버튼이 위에 옴)
        set auxWheelArea = MSFdfCreateWheelArea(skRoot)
        call GUISetPoint(auxWheelArea, skRoot, R2I(AUXX), AUX_ROW_Y)
        call GUISetSize(auxWheelArea, 300, AUX_ROW_H * AUX_ROWS)
        call DzFrameSetScriptByCode(auxWheelArea, 6, function onAuxWheel, false)

        loop
            exitwhen row >= AUX_ROWS
            set cy = AUX_ROW_Y + row * AUX_ROW_H
            set auxRowBg[row] = GUICreateImage(skRoot)
            call GUISetPoint(auxRowBg[row], skRoot, R2I(AUXX), cy)
            call GUISetSize(auxRowBg[row], 300, 52)
            call GUISetImage(auxRowBg[row], "UI_plate_none.tga")
            call GUISetAlpha(auxRowBg[row], 120)

            set auxRowIcon[row] = GUICreateImage(skRoot)
            call GUISetPoint(auxRowIcon[row], skRoot, R2I(AUXX) + 8, cy + 6)
            call GUISetSize(auxRowIcon[row], 40, 40)

            set auxRowText[row] = GUICreateText(skRoot)
            call GUISetPoint(auxRowText[row], skRoot, R2I(AUXX) + 56, cy + 6)
            call GUISetSize(auxRowText[row], 168, 44)
            call GUISetFont(auxRowText[row], MAP_FONT_LIGHT, 11)

            set auxRowBtn[row] = GUICreateButton(skRoot)
            call GUISetPoint(auxRowBtn[row], skRoot, R2I(AUXX) + 232, cy + 12)
            call GUISetSize(auxRowBtn[row], 62, 28)
            call DzFrameSetScriptByCode(auxRowBtn[row], 1, function onAuxRowClick, false)
            call DzFrameSetScriptByCode(auxRowBtn[row], 6, function onAuxWheel, false)
            set lbl = GUICreateText(auxRowBtn[row])
            call GUISetPointEx(lbl, GUI_DOCK_MIDDLECENTER, auxRowBtn[row], GUI_DOCK_MIDDLECENTER, 0, 0)
            call GUISetFont(lbl, MAP_FONT_BOLD, 12)
            call GUISetText(lbl, "|cffd4af37장착|r")

            call GUIShow(auxRowBg[row], false)
            call GUIShow(auxRowIcon[row], false)
            call GUIShow(auxRowText[row], false)
            call GUIShow(auxRowBtn[row], false)
            set row = row + 1
        endloop

        // 스크롤 위치바 (track 고정 + thumb 위치표시) — image라 입력 비소비
        set auxScrollTrack = GUICreateImage(skRoot)
        call GUISetPoint(auxScrollTrack, skRoot, R2I(AUXX) + 306, AUX_ROW_Y)
        call GUISetSize(auxScrollTrack, 10, AUX_ROW_H * AUX_ROWS)
        call GUISetImage(auxScrollTrack, "UI_scroll_track.tga")
        call GUISetAlpha(auxScrollTrack, 255)
        call GUIShow(auxScrollTrack, false)

        set auxScrollThumb = GUICreateImage(skRoot)
        call GUISetPoint(auxScrollThumb, skRoot, R2I(AUXX) + 306, AUX_ROW_Y)
        call GUISetSize(auxScrollThumb, 10, 40)
        call GUISetImage(auxScrollThumb, "UI_scroll_handle.tga")
        call GUISetAlpha(auxScrollThumb, 255)
        call GUIShow(auxScrollThumb, false)
    endfunction

    private function onMapLoad takes nothing returns nothing
        local integer tempFrame
        local integer btnTxt

        set skLayer = GUICreateContainer(GUIGetScreen())
        call GUISetPoint(skLayer, GUIGetScreen(), 0, 0)
        call GUISetSize(skLayer, GUIGetScreenWidth(), GUIGetScreenHeight())
        call GUIShow(skLayer, false)

        set skRoot = GUICreateContainer(skLayer)
        call GUISetPoint(skRoot, skLayer, skX, skY)
        call GUISetSize(skRoot, SK_W, SK_H)

        set skBackdrop = GUICreateImage(skRoot)
        call GUISetPoint(skBackdrop, skRoot, 0, 0)
        call GUISetSize(skBackdrop, SK_W, SK_H)
        call GUISetImage(skBackdrop, "UI_plate_none.tga")
        call GUISetAlpha(skBackdrop, 235)

        set skCaption = GUICreateButton(skRoot)
        call GUISetPoint(skCaption, skRoot, 0, 0)
        call GUISetSize(skCaption, SK_W - 40.0, 40)
        call DzFrameSetScriptByCode(skCaption, 2, function onCapEnter, false)
        call DzFrameSetScriptByCode(skCaption, 3, function onCapLeave, false)

        set skTitle = GUICreateText(skRoot)
        call GUISetPointEx(skTitle, GUI_DOCK_MIDDLECENTER, skCaption, GUI_DOCK_MIDDLECENTER, 0, 0)
        call GUISetFont(skTitle, MAP_FONT_BOLD, 20)
        call GUISetText(skTitle, "|cffd4af37스킬 강화|r")

        set skCloseBtn = GUICreateButton(skRoot)
        call GUISetPoint(skCloseBtn, skRoot, R2I(SK_W) - 40, 8)
        call GUISetSize(skCloseBtn, 32, 32)
        call DzFrameSetScriptByCode(skCloseBtn, 1, function onClose, false)
        set tempFrame = GUICreateImage(skCloseBtn)
        call GUISetPoint(tempFrame, skCloseBtn, 0, 0)
        call GUISetSize(tempFrame, 32, 32)
        call GUISetImage(tempFrame, "UI_icon_close.tga")

        // 카드 휠 스크롤 영역 (MS_WheelArea 투명버튼 — 카드보다 먼저 생성해 카드/버튼이 위에 옴)
        set skWheelArea = MSFdfCreateWheelArea(skRoot)
        call GUISetPoint(skWheelArea, skRoot, 14, R2I(SK_ROW_Y))
        call GUISetSize(skWheelArea, R2I(CARD_W) - 14, R2I(SK_ROW_H * I2R(SK_CARDS)))
        call DzFrameSetScriptByCode(skWheelArea, 6, function onWheel, false)

        call createCard(0, 54)
        call createCard(1, 204)
        call createCard(2, 354)
        call createCard(3, 504)

        call createAuxPanel()

        // 스크롤 위치바 (track 고정 + thumb 위치표시) — image라 입력 비소비
        set skScrollTrack = GUICreateImage(skRoot)
        call GUISetPoint(skScrollTrack, skRoot, R2I(CARD_W) - 12, R2I(SK_ROW_Y))
        call GUISetSize(skScrollTrack, 10, R2I(SK_ROW_H * I2R(SK_CARDS)))
        call GUISetImage(skScrollTrack, "UI_scroll_track.tga")
        call GUISetAlpha(skScrollTrack, 255)

        set skScrollThumb = GUICreateImage(skRoot)
        call GUISetPoint(skScrollThumb, skRoot, R2I(CARD_W) - 12, R2I(SK_ROW_Y))
        call GUISetSize(skScrollThumb, 10, 40)
        call GUISetImage(skScrollThumb, "UI_scroll_handle.tga")
        call GUISetAlpha(skScrollThumb, 255)

        set skSilverText = GUICreateText(skRoot)
        call GUISetPoint(skSilverText, skRoot, 16, R2I(SK_H) - 28)
    endfunction

    // 동적 스킬 툴팁 생성 (gx_cursorFrame 자식 → 마우스 추종)
    // gx_cursorFrame은 GxCursor가 0.01s에 생성하므로 지연 초기화
    private function createTip takes nothing returns nothing
        set skTipRoot = GUICreateContainer(gx_cursorFrame)
        call GUISetPoint(skTipRoot, gx_cursorFrame, 26, 44)
        call GUISetSize(skTipRoot, TIP_W, TIP_H)

        set skTipBg = GUICreateImage(skTipRoot)
        call GUISetPoint(skTipBg, skTipRoot, 0, 0)
        call GUISetSize(skTipBg, TIP_W, TIP_H)
        call GUISetImage(skTipBg, "Textures\\black32.blp")
        call GUISetAlpha(skTipBg, 238)

        set skTipTitle = GUICreateText(skTipRoot)
        call GUISetPoint(skTipTitle, skTipRoot, 14, 12)
        call GUISetSize(skTipTitle, TIP_W - 28.0, 24)
        call GUISetFont(skTipTitle, MAP_FONT_BOLD, 16)

        set skTipBody = GUICreateText(skTipRoot)
        call GUISetPoint(skTipBody, skTipRoot, 14, 42)
        call GUISetSize(skTipBody, TIP_W - 28.0, TIP_H - 54.0)
        call GUISetFont(skTipBody, MAP_FONT_LIGHT, 12)

        call GUIShow(skTipRoot, false)
    endfunction

    private function initTriggers takes nothing returns nothing
        local trigger t

        set t = CreateTrigger()
        call TriggerRegisterTimerEvent(t, 0.00, false)
        call TriggerAddAction(t, function onMapLoad)

        set t = CreateTrigger()
        call TriggerRegisterTimerEvent(t, 0.05, false)
        call TriggerAddAction(t, function createTip)

        set t = CreateTrigger()
        call TriggerRegisterTimerEvent(t, 0.10, true)
        call TriggerAddAction(t, function update)

        set t = CreateTrigger()
        call DzTriggerRegisterMouseEventByCode(t, 0x1, 1, false, function onLMBDown)
        set t = CreateTrigger()
        call DzTriggerRegisterMouseEventByCode(t, 0x1, 0, false, function onLMBUp)

        set t = CreateTrigger()
        call DzTriggerRegisterSyncData(t, SYNC_SKILLUP, false)
        call TriggerAddAction(t, function onSyncUp)

        set t = CreateTrigger()
        call DzTriggerRegisterSyncData(t, SYNC_AUX_EQ, false)
        call TriggerAddAction(t, function onSyncAuxEq)

        set t = CreateTrigger()
        call DzTriggerRegisterSyncData(t, SYNC_AUX_UNEQ, false)
        call TriggerAddAction(t, function onSyncAuxUneq)

        set t = null
    endfunction

    private function onInit takes nothing returns nothing
        call initTriggers()
    endfunction

endscope
