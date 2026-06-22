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
