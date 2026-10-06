(function () {
  'use strict';

  // ===== 설정 =====
  var SLOT_COUNT = 4;      // 표시되는 슬롯 수
  var UNLOCKED_SLOTS = 3;  // 해금된 슬롯 수
  var PRESET_COUNT = 3;

  // 카테고리별 아이콘 색 / SVG
  var CATEGORIES = {
    luck:  { color: 'var(--c-luck)',  icon: '<path d="M12 3l2.2 5.8L20 11l-5.8 2.2L12 19l-2.2-5.8L4 11l5.8-2.2z"/>' },
    guard: { color: 'var(--c-guard)', icon: '<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/>' },
    econ:  { color: 'var(--c-econ)',  icon: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3.5"/>' },
    speed: { color: 'var(--c-speed)', icon: '<path d="M13 3L5 14h6l-1 7 8-11h-6z"/>' }
  };

  // 보유 보조스킬 목록 (실제 데이터로 교체)
  var SUB_SKILLS = [
    { id: 'luck1',  cat: 'luck',  name: '행운의 손길', lv: 3, desc: '강화 성공률 +[N]%' },
    { id: 'luck2',  cat: 'luck',  name: '장인의 집중', lv: 5, desc: '강화 성공률 +[N]%' },
    { id: 'guard1', cat: 'guard', name: '수호의 결계', lv: 4, desc: '파괴 확률 -[N]%' },
    { id: 'guard2', cat: 'guard', name: '하락 방지',   lv: 2, desc: '실패 시 하락 확률 -[N]%' },
    { id: 'econ1',  cat: 'econ',  name: '절약의 지혜', lv: 6, desc: '강화 비용 -[N]%' },
    { id: 'econ2',  cat: 'econ',  name: '메소 회수',   lv: 1, desc: '실패 시 비용 [N]% 환급' },
    { id: 'speed1', cat: 'speed', name: '신속 강화',   lv: 3, desc: '강화 연출 속도 x[N]' },
    { id: 'speed2', cat: 'speed', name: '연속 시도',   lv: 2, desc: '자동 강화 횟수 +[N]' }
  ];

  var byId = {};
  SUB_SKILLS.forEach(function (s) { byId[s.id] = s; });

  // ===== 상태 =====
  var state = {
    open: true,
    preset: 0,   // 보고 있는(편집 중인) 프리셋
    applied: 0,  // 실제로 적용된 프리셋
    presets: [['luck2', 'guard1', 'econ1'], ['guard1', 'guard2'], []]
  };
  while (state.presets.length < PRESET_COUNT) state.presets.push([]);

  // ===== DOM =====
  var $toggle = document.getElementById('subskill-toggle');
  var $toggleCount = document.getElementById('subskill-toggle-count');
  var $panel = document.getElementById('subskill-panel');
  var $equipCount = document.getElementById('subskill-equip-count');
  var $presetTabs = document.getElementById('preset-tabs');
  var $slotGrid = document.getElementById('slot-grid');
  var $owned = document.getElementById('owned-list');
  var $applyBtn = document.getElementById('apply-btn');
  var $appliedLabel = document.getElementById('applied-label');

  function esc(s) {
    return String(s).replace(/[&<>"']/g, function (c) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
    });
  }

  function iconHtml(cat) {
    return '<div class="skill-icon"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linejoin="round">' +
      CATEGORIES[cat].icon + '</svg></div>';
  }

  function equipped() {
    return state.presets[state.preset];
  }

  // ===== 동작 =====
  function setOpen(open) {
    state.open = open;
    render();
  }

  function equip(id) {
    var eq = equipped();
    if (eq.indexOf(id) !== -1 || eq.length >= UNLOCKED_SLOTS) return;
    eq.push(id);
    render();
  }

  function unequip(id) {
    state.presets[state.preset] = equipped().filter(function (x) { return x !== id; });
    render();
  }

  function selectPreset(i) {
    state.preset = i;
    render();
  }

  function clearAll() {
    state.presets[state.preset] = [];
    render();
  }

  function apply() {
    if (state.preset === state.applied) return;
    state.applied = state.preset;
    render();
    // TODO: 게임 로직에 적용된 보조스킬 반영
    // onApply(state.presets[state.applied]);
  }

  // ===== 렌더 =====
  function render() {
    var eq = equipped();

    // 토글 버튼 / 패널 표시
    $toggle.setAttribute('aria-expanded', state.open ? 'true' : 'false');
    $panel.hidden = !state.open;
    $toggleCount.textContent = state.presets[state.applied].length + '/' + UNLOCKED_SLOTS;
    $equipCount.textContent = '장착 ' + eq.length + ' / ' + UNLOCKED_SLOTS;

    // 프리셋 탭
    $presetTabs.innerHTML = state.presets.map(function (ids, i) {
      return '<button type="button" class="preset-tab' + (ids.length ? ' has-skills' : '') + '"' +
        ' data-action="preset" data-index="' + i + '"' +
        ' aria-pressed="' + (i === state.preset) + '" aria-label="프리셋 ' + (i + 1) + '">' + (i + 1) + '</button>';
    }).join('');

    // 장착 슬롯
    var slots = '';
    for (var i = 0; i < SLOT_COUNT; i++) {
      if (i >= UNLOCKED_SLOTS) {
        slots += '<div class="slot slot--locked">' +
          '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 018 0v3"/></svg>' +
          '<span>잠긴 슬롯</span></div>';
        continue;
      }
      var sk = byId[eq[i]];
      if (!sk) {
        slots += '<div class="slot slot--empty">' +
          '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><path d="M12 6v12M6 12h12"/></svg>' +
          '<span>빈 슬롯 ' + (i + 1) + '</span></div>';
        continue;
      }
      slots += '<div class="slot slot--filled" style="--cat:' + CATEGORIES[sk.cat].color + '">' +
        iconHtml(sk.cat) +
        '<div class="slot__name">' + esc(sk.name) + '</div>' +
        '<button type="button" class="slot__unequip" data-action="unequip" data-id="' + sk.id + '" aria-label="' + esc(sk.name) + ' 해제">해제</button>' +
        '</div>';
    }
    $slotGrid.innerHTML = slots;

    // 보유 보조스킬
    $owned.innerHTML = SUB_SKILLS.map(function (s) {
      var on = eq.indexOf(s.id) !== -1;
      var btn;
      if (on) {
        btn = '<button type="button" class="owned-card__btn btn-unequip" data-action="unequip" data-id="' + s.id + '" aria-label="' + esc(s.name) + ' 해제">해제</button>';
      } else if (eq.length < UNLOCKED_SLOTS) {
        btn = '<button type="button" class="owned-card__btn btn-equip" data-action="equip" data-id="' + s.id + '" aria-label="' + esc(s.name) + ' 장착">장착</button>';
      } else {
        btn = '<button type="button" class="owned-card__btn btn-full" disabled>가득</button>';
      }
      return '<div class="owned-card' + (on ? ' is-equipped' : '') + '" style="--cat:' + CATEGORIES[s.cat].color + '">' +
        iconHtml(s.cat) +
        '<div class="owned-card__info">' +
          '<div class="owned-card__title"><span class="owned-card__name">' + esc(s.name) + '</span><span class="owned-card__lv">Lv.' + s.lv + '</span></div>' +
          '<div class="owned-card__desc">' + esc(s.desc) + '</div>' +
        '</div>' + btn + '</div>';
    }).join('');

    // 적용 버튼: 이미 적용된 프리셋이면 비활성화
    var isApplied = state.preset === state.applied;
    $applyBtn.disabled = isApplied;
    $applyBtn.textContent = isApplied ? '적용됨' : '적용';
    $appliedLabel.textContent = '프리셋 ' + (state.applied + 1);
  }

  // ===== 이벤트 =====
  $toggle.addEventListener('click', function () { setOpen(!state.open); });

  $panel.addEventListener('click', function (e) {
    var el = e.target.closest('[data-action]');
    if (!el || el.disabled) return;
    switch (el.dataset.action) {
      case 'close':   setOpen(false); break;
      case 'preset':  selectPreset(Number(el.dataset.index)); break;
      case 'clear':   clearAll(); break;
      case 'equip':   equip(el.dataset.id); break;
      case 'unequip': unequip(el.dataset.id); break;
      case 'apply':   apply(); break;
    }
  });

  render();
})();
