const API = '/api';
const localUser = localStorage.getItem('chat-username') || '나';

let chatLog = [];        // { username, text, time, mine }
let pollTimer = null;

// ── 탭 전환 ─────────────────────────────────────────────
document.querySelectorAll('.tab').forEach(btn => {
  btn.addEventListener('click', () => {
    document.querySelectorAll('.tab').forEach(b => b.classList.remove('active'));
    document.querySelectorAll('.panel').forEach(p => p.classList.remove('active'));
    btn.classList.add('active');
    document.getElementById(btn.dataset.tab).classList.add('active');
    if (btn.dataset.tab === 'admin') loadAdminStatus();
  });
});

// ── SQS 채팅 ────────────────────────────────────────────
async function sendChat() {
  const usernameEl = document.getElementById('username');
  const textEl = document.getElementById('chat-text');
  const username = usernameEl.value.trim() || '익명';
  const text = textEl.value.trim();
  if (!text) return;

  localStorage.setItem('chat-username', username);
  textEl.value = '';

  // 낙관적 렌더링
  appendMessage({ username, text, time: nowTime(), mine: true });

  await fetch(`${API}/chat/send`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, text }),
  }).catch(() => {});
}

async function pollChat() {
  try {
    const res = await fetch(`${API}/chat/messages`);
    const { messages } = await res.json();
    messages.forEach(m => {
      // 내가 낙관적으로 추가한 것과 중복 방지 (username+text 기준)
      const isDup = chatLog.some(c => c.mine && c.username === m.username && c.text === m.text);
      if (!isDup) appendMessage({ ...m, mine: false });
    });
  } catch (_) {}
  pollTimer = setTimeout(pollChat, 3000);
}

function appendMessage(msg) {
  chatLog.push(msg);
  const box = document.getElementById('chat-messages');
  const empty = box.querySelector('.chat-empty');
  if (empty) empty.remove();

  const bubble = document.createElement('div');
  bubble.className = `msg-bubble ${msg.mine ? 'me' : 'other'}`;
  bubble.innerHTML = `
    <span class="msg-meta">${escHtml(msg.username)} · ${msg.time}</span>
    <span class="msg-text">${escHtml(msg.text)}</span>
  `;
  box.appendChild(bubble);
  box.scrollTop = box.scrollHeight;
}

function nowTime() {
  return new Date().toLocaleTimeString('ko-KR', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
}

// ── SNS → Slack ──────────────────────────────────────────
async function sendSlack() {
  const subject = document.getElementById('slack-subject').value.trim();
  const message = document.getElementById('slack-message').value.trim();
  const statusEl = document.getElementById('slack-status');

  if (!subject || !message) {
    setStatus(statusEl, '제목과 메시지를 모두 입력하세요.', 'error');
    return;
  }

  setStatus(statusEl, '전송 중...', '');
  try {
    const res = await fetch(`${API}/slack/send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ subject, message }),
    });
    if (res.ok) {
      const { messageId } = await res.json();
      setStatus(statusEl, `✅ Slack 전송 완료 (SNS MessageId: ${messageId})`, 'success');
    } else {
      const { detail } = await res.json();
      setStatus(statusEl, `❌ ${detail}`, 'error');
    }
  } catch (e) {
    setStatus(statusEl, `❌ 네트워크 오류: ${e.message}`, 'error');
  }
}

// ── 이메일 발송 ──────────────────────────────────────────
async function sendEmail() {
  const from_email = document.getElementById('from-email').value.trim();
  const to_email   = document.getElementById('to-email').value.trim();
  const subject    = document.getElementById('email-subject').value.trim();
  const message    = document.getElementById('email-message').value.trim();
  const statusEl   = document.getElementById('email-status');

  if (!from_email || !to_email || !subject || !message) {
    setStatus(statusEl, '모든 항목을 입력하세요.', 'error');
    return;
  }

  setStatus(statusEl, '발송 중...', '');
  try {
    const res = await fetch(`${API}/email/send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ from_email, to_email, subject, message }),
    });
    if (res.ok) {
      setStatus(statusEl, '✅ 이메일 발송 완료!', 'success');
    } else {
      const { detail } = await res.json();
      setStatus(statusEl, `❌ ${detail}`, 'error');
    }
  } catch (e) {
    setStatus(statusEl, `❌ 네트워크 오류: ${e.message}`, 'error');
  }
}

// ── 관리자 ───────────────────────────────────────────────
async function loadAdminStatus() {
  document.getElementById('admin-sqs').innerHTML = '<span class="loading">로딩 중...</span>';
  document.getElementById('admin-sns').innerHTML = '<span class="loading">로딩 중...</span>';
  document.getElementById('admin-ses').innerHTML = '<span class="loading">로딩 중...</span>';
  await Promise.all([fetchSQS(), fetchSNS(), fetchSES()]);
}

async function fetchSQS() {
  const el = document.getElementById('admin-sqs');
  try {
    const { queues } = await fetch(`${API}/admin/sqs`).then(r => r.json());
    const rows = queues.map(q => {
      if (q.status === 'error') {
        return `<tr><td>${escHtml(q.label)}</td><td colspan="3"><span class="err-text">${escHtml(q.error)}</span></td></tr>`;
      }
      const wBadge = countBadge(q.waiting);
      const fBadge = countBadge(q.in_flight, 'warn');
      return `<tr>
        <td class="cell-name">${escHtml(q.label)}</td>
        <td class="cell-num">${wBadge}</td>
        <td class="cell-num">${fBadge}</td>
        <td class="cell-num">${q.retention_days}일</td>
      </tr>`;
    }).join('');
    el.innerHTML = `
      <table class="status-table">
        <thead><tr><th>큐 이름</th><th>대기 중</th><th>처리 중</th><th>보관 기간</th></tr></thead>
        <tbody>${rows}</tbody>
      </table>`;
  } catch (e) {
    el.innerHTML = `<span class="err-text">오류: ${e.message}</span>`;
  }
}

async function fetchSNS() {
  const el = document.getElementById('admin-sns');
  try {
    const data = await fetch(`${API}/admin/sns`).then(r => r.json());
    if (data.status === 'error') { el.innerHTML = `<span class="err-text">${escHtml(data.error)}</span>`; return; }

    const { topic, subscriptions } = data;
    const subRows = subscriptions.map(s => `
      <tr>
        <td><span class="proto-tag">${escHtml(s.protocol)}</span></td>
        <td class="cell-endpoint">${escHtml(s.endpoint)}</td>
        <td>${s.confirmed ? '<span class="pill ok">확인됨</span>' : '<span class="pill warn">대기 중</span>'}</td>
      </tr>`).join('') || '<tr><td colspan="3" class="empty-row">구독 없음</td></tr>';

    el.innerHTML = `
      <div class="stat-row">
        <div class="stat-card"><span class="stat-val">${topic.confirmed}</span><span class="stat-label">구독 확인됨</span></div>
        <div class="stat-card warn"><span class="stat-val">${topic.pending}</span><span class="stat-label">구독 대기 중</span></div>
        <div class="stat-card muted"><span class="stat-val">${topic.deleted}</span><span class="stat-label">구독 삭제됨</span></div>
      </div>
      <table class="status-table mt-8">
        <thead><tr><th>프로토콜</th><th>엔드포인트</th><th>상태</th></tr></thead>
        <tbody>${subRows}</tbody>
      </table>`;
  } catch (e) {
    el.innerHTML = `<span class="err-text">오류: ${e.message}</span>`;
  }
}

async function fetchSES() {
  const el = document.getElementById('admin-ses');
  try {
    const data = await fetch(`${API}/admin/ses`).then(r => r.json());
    if (data.status === 'error') { el.innerHTML = `<span class="err-text">${escHtml(data.error)}</span>`; return; }

    const { quota, identities } = data;
    const pct = quota.max_24h > 0 ? ((quota.sent_24h / quota.max_24h) * 100).toFixed(1) : 0;
    const idRows = identities.map(i => `
      <tr>
        <td>${escHtml(i.email)}</td>
        <td>${i.verified ? '<span class="pill ok">인증됨</span>' : '<span class="pill warn">미인증</span>'}</td>
      </tr>`).join('') || '<tr><td colspan="2" class="empty-row">인증된 이메일 없음</td></tr>';

    el.innerHTML = `
      <div class="stat-row">
        <div class="stat-card"><span class="stat-val">${quota.sent_24h.toLocaleString()}</span><span class="stat-label">오늘 발송</span></div>
        <div class="stat-card muted"><span class="stat-val">${quota.max_24h.toLocaleString()}</span><span class="stat-label">24h 한도</span></div>
        <div class="stat-card muted"><span class="stat-val">${quota.max_rate}/초</span><span class="stat-label">최대 발송률</span></div>
      </div>
      <div class="quota-bar-wrap">
        <div class="quota-bar" style="width:${pct}%"></div>
        <span class="quota-label">${pct}% 사용</span>
      </div>
      <table class="status-table mt-8">
        <thead><tr><th>이메일</th><th>인증 상태</th></tr></thead>
        <tbody>${idRows}</tbody>
      </table>`;
  } catch (e) {
    el.innerHTML = `<span class="err-text">오류: ${e.message}</span>`;
  }
}

function countBadge(n, variant = '') {
  const cls = n > 0 ? (variant === 'warn' ? 'pill warn' : 'pill ok') : 'pill muted';
  return `<span class="${cls}">${n}</span>`;
}

// ── 유틸 ────────────────────────────────────────────────
function setStatus(el, text, type) {
  el.textContent = text;
  el.className = `status ${type}`;
}

function escHtml(str) {
  return str.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

// ── 초기화 ───────────────────────────────────────────────
(function init() {
  const usernameEl = document.getElementById('username');
  if (usernameEl) usernameEl.value = localUser;

  const chatBox = document.getElementById('chat-messages');
  chatBox.innerHTML = '<span class="chat-empty">메시지가 없습니다. 채팅을 시작해보세요!</span>';

  pollChat();
})();
