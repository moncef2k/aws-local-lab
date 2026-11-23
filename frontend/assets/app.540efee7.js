const COUNT = 12;      // calls per run
const tally = {};      // container id -> number of answers so far

// A stable colour per name, so the same instance always looks the same.
function colour(name) {
  let h = 0;
  for (const c of name) h = (h * 31 + c.charCodeAt(0)) % 360;
  return `hsl(${h} 60% 45%)`;
}

async function whoami() {
  const start = performance.now();
  const res = await fetch('/whoami', { cache: 'no-store' });   // no-store: never answer from the browser cache
  const { hostname } = await res.json();
  return { hostname, ms: Math.round(performance.now() - start) };
}

function showTally() {
  const total = Object.values(tally).reduce((a, b) => a + b, 0);
  document.getElementById('tally').replaceChildren(...Object.entries(tally).sort().map(([name, n]) => {
    const li = document.createElement('li');
    li.innerHTML = `<span class="name"></span><span class="bar"></span><span>${n}</span>`;
    li.querySelector('.name').textContent = name;
    Object.assign(li.querySelector('.bar').style, { background: colour(name), width: `${(n / total) * 14}rem` });
    return li;
  }));
}

async function run() {
  const button = document.getElementById('again');
  button.disabled = true;
  for (let i = 1; i <= COUNT; i++) {
    try {
      const { hostname, ms } = await whoami();
      tally[hostname] = (tally[hostname] || 0) + 1;
      const li = document.createElement('li');
      li.textContent = `#${i} ${hostname} ${ms} ms`;
      li.style.borderColor = colour(hostname);
      document.getElementById('calls').appendChild(li);
      showTally();
    } catch (err) {
      document.getElementById('calls').insertAdjacentHTML('beforeend', `<li class="bad">#${i} failed</li>`);
    }
  }
  button.disabled = false;
}

async function health() {
  const el = document.getElementById('health');
  try {
    const res = await fetch('/health', { cache: 'no-store' });
    el.textContent = `GET /health: HTTP ${res.status} ${JSON.stringify(await res.json())}`;
    el.className = res.ok ? 'ok' : 'bad';
  } catch (err) {
    el.textContent = 'GET /health failed';
    el.className = 'bad';
  }
}

document.getElementById('again').addEventListener('click', run);
health();
run();
