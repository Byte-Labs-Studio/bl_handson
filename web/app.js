const $ = (id) => document.getElementById(id);

const panel = $('panel');
const gauge = $('gauge');
const toast = $('toast');

let maxStrikes = 3;
let toastTimer;

const percent = (value) => `${Math.max(0, Math.min(100, value * 100)).toFixed(1)}%`;

function meter(value, className = '') {
    return `<div class="meter ${className}"><div class="fill" style="width:${percent(value)}"></div></div>`;
}

function renderStrikes(count) {
    const strikes = $('strikes');

    strikes.innerHTML = '';

    for (let i = 0; i < maxStrikes; i++) {
        const dot = document.createElement('span');

        if (i < count) dot.className = 'hit';

        strikes.appendChild(dot);
    }
}

const gauges = {
    progress: (g) => meter(g.value),

    turn: (g) => {
        let html = meter(g.value);

        if (g.strain !== undefined && g.strain !== null) {
            html += `<div class="readout"><span>Breaking it loose</span></div>${meter(g.strain, 'strain')}`;
        }

        return html;
    },

    torque: (g) => {
        const max = g.spec * 1.3;
        const lo = (g.spec * 0.95) / max;
        const hi = (g.spec * 1.07) / max;
        const state = g.value > g.spec * 1.07 ? 'warn' : g.clicked ? 'ok' : '';

        return `<div class="meter"><div class="zone" style="left:${percent(lo)};width:${percent(hi - lo)}"></div>`
            + `<div class="fill" style="width:${percent(g.value / max)}"></div></div>`
            + `<div class="readout"><span>Spec ${g.spec} Nm</span><b class="${state}">${g.value} Nm${g.clicked ? ' · CLICK' : ''}</b></div>`;
    },

    chain: (g) => {
        const max = 60;
        const inBand = g.slack >= g.lo && g.slack <= g.hi;
        const aligned = Math.abs(g.skew) <= g.tolerance;
        const skew = Math.max(-1, Math.min(1, g.skew / 1.5));
        const slackText = g.goal === 'loose' ? `${g.slack} mm` : `${g.slack} mm (${g.lo}-${g.hi})`;

        return `<div class="readout"><span>Chain slack</span><b class="${g.goal === 'set' ? (inBand ? 'ok' : 'warn') : ''}">${slackText}</b></div>`
            + `<div class="meter"><div class="zone" style="left:${percent(g.lo / max)};width:${percent((g.hi - g.lo) / max)}"></div>`
            + `<div class="pin" style="left:${percent(g.slack / max)}"></div></div>`
            + `<div class="readout"><span>Adjuster marks</span><b class="${aligned ? 'ok' : 'warn'}">${aligned ? 'Matched' : g.skew > 0 ? 'Right side long' : 'Left side long'}</b></div>`
            + `<div class="meter"><div class="zone" style="left:${percent(0.5 - g.tolerance / 3)};width:${percent(g.tolerance / 1.5)}"></div>`
            + `<div class="pin" style="left:${percent(0.5 + skew / 2)}"></div></div>`;
    },

    loosen: (g) => {
        const side = (label, value) => {
            const done = value >= 1;

            return `<div class="readout"><span>${label} adjuster</span><b class="${done ? 'ok' : ''}">${done ? 'Backed off' : `${(Math.min(value, 1) * g.goal).toFixed(1)} / ${g.goal} turns`}</b></div>`
                + meter(Math.min(value, 1));
        };

        return side('Left', g.left) + side('Right', g.right);
    },

    count: (g) => {
        let dots = '';

        for (let i = 0; i < g.goal; i++) dots += `<span class="${i < g.value ? 'on' : ''}"></span>`;

        return `<div class="dots">${dots}</div>`;
    },
};

function showToast(kind, text) {
    clearTimeout(toastTimer);

    toast.textContent = text;
    toast.className = `toast show ${kind}`;

    toastTimer = setTimeout(() => {
        toast.className = 'toast';
    }, kind === 'strike' ? 2600 : 1400);
}

const actions = {
    visible: (data) => {
        panel.classList.toggle('hidden', !data.visible);

        if (data.title) $('title').textContent = data.title;

        if (!data.visible) {
            gauge.innerHTML = '';
            toast.className = 'toast';
            return;
        }

        renderStrikes(0);
    },

    step: (data) => {
        $('count').textContent = `${data.index} / ${data.total}`;
        $('barFill').style.width = percent((data.index - 1) / data.total);
        $('label').textContent = data.label;
        $('hint').textContent = data.hint;
        gauge.innerHTML = '';
    },

    gauge: (data) => {
        const render = gauges[data.gauge.type];

        gauge.innerHTML = render ? render(data.gauge) : '';
    },

    flash: (data) => {
        if (data.maxStrikes) maxStrikes = data.maxStrikes;
        if (data.strikes !== undefined && data.strikes !== null) renderStrikes(data.strikes);

        showToast(data.kind, data.text);
    },
};

window.addEventListener('message', (event) => {
    const data = event.data;
    const action = data && actions[data.action];

    if (action) action(data);
});
