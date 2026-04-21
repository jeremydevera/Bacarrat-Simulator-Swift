const TABLE_COUNT = 30;
const STOP_LOSS_LEVELS = 20;
const DEFAULT_STOP_LOSS_LEVEL = 11;
const STRATEGIES = {
    classic: "Classic Martingale",
    mod: "Mod Martingale",
};
const SPEED_LABELS = {
    2: "2x",
    50: "50x",
    100: "100x",
};
const RESULT_COLORS = {
    Banker: "#ef6b63",
    Player: "#5ea2ff",
    Tie: "#4fd08d",
};

const pesoFormatter = new Intl.NumberFormat("en-PH", {
    style: "currency",
    currency: "PHP",
    maximumFractionDigits: 0,
});
const fullDayFormatter = new Intl.DateTimeFormat("en-PH", {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
});
const timestampFormatter = new Intl.DateTimeFormat("en-PH", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    second: "2-digit",
});

const elements = {
    tabs: Array.from(document.querySelectorAll(".tab-button")),
    panels: Array.from(document.querySelectorAll(".panel")),
    strategyLabel: document.querySelector("#strategy-label"),
    currentBetLabel: document.querySelector("#current-bet-label"),
    activeTableLabel: document.querySelector("#active-table-label"),
    queuedLabel: document.querySelector("#queued-label"),
    speedLabel: document.querySelector("#speed-label"),
    totalProfitLabel: document.querySelector("#total-profit-label"),
    strategySelect: document.querySelector("#strategy-select"),
    sideSelect: document.querySelector("#side-select"),
    startingBetInput: document.querySelector("#starting-bet-input"),
    stopLossSelect: document.querySelector("#stop-loss-select"),
    tableTimerInput: document.querySelector("#table-timer-input"),
    speedSelect: document.querySelector("#speed-select"),
    warningField: document.querySelector("#warning-field"),
    warningLevelInput: document.querySelector("#warning-level-input"),
    autoContinueToggle: document.querySelector("#auto-continue-toggle"),
    saveHistoryToggle: document.querySelector("#save-history-toggle"),
    simulationStatus: document.querySelector("#simulation-status"),
    simTimeLabel: document.querySelector("#sim-time-label"),
    toggleSessionButton: document.querySelector("#toggle-session-button"),
    stopButton: document.querySelector("#stop-button"),
    clearHistoryButton: document.querySelector("#clear-history-button"),
    tableGrid: document.querySelector("#table-grid"),
    historyModeLabel: document.querySelector("#history-mode-label"),
    historySummaryCopy: document.querySelector("#history-summary-copy"),
    handsTodayLabel: document.querySelector("#hands-today-label"),
    historyProfitCopy: document.querySelector("#history-profit-copy"),
    historyListTitle: document.querySelector("#history-list-title"),
    historyList: document.querySelector("#history-list"),
    maxLossList: document.querySelector("#max-loss-list"),
    trendTitle: document.querySelector("#trend-title"),
    resultPieChart: document.querySelector("#result-pie-chart"),
    profitLineChart: document.querySelector("#profit-line-chart"),
    stopLossModal: document.querySelector("#stop-loss-modal"),
    stopLossMessage: document.querySelector("#stop-loss-message"),
    continueButton: document.querySelector("#continue-button"),
    haltButton: document.querySelector("#halt-button"),
};

const state = createInitialState();

initialize();

function initialize() {
    bindEvents();
    populateStopLossOptions();
    renderAll();
}

function createInitialState() {
    return {
        strategy: "classic",
        saveHistoryEnabled: false,
        totalProfit: 0,
        warningLevel: 5,
        startingBet: 20,
        tableTimer: 20,
        selectedStopLoss: 20_480,
        selectedSide: "Player",
        activeBet: null,
        nextBetAmount: 20,
        nextStreakStep: 1,
        currentStreakGroupID: makeID(),
        status: "Press Play to start the session.",
        isSessionRunning: false,
        selectedSpeed: 2,
        autoContinueEnabled: false,
        simulationReferenceDate: new Date(),
        simCurrentSeconds: 0,
        lastResumePerf: null,
        tables: makeInitialTables(20),
        historyEntries: [],
        dailyProfits: new Map(),
        maxLossRecords: new Map(),
        storedBetsQueue: [],
        stopLossAlert: null,
        stopLossDismissTimeout: null,
        eventTimeoutID: null,
        renderFrameID: null,
        activeTab: "simulator",
    };
}

function bindEvents() {
    elements.tabs.forEach((tab) => {
        tab.addEventListener("click", () => {
            state.activeTab = tab.dataset.tabTarget;
            renderTabs();
            renderHistory();
            renderAnalytics();
        });
    });

    elements.strategySelect.addEventListener("change", (event) => {
        state.strategy = event.target.value;
        applyStartingBetChanges(true);
        renderAll();
    });

    elements.sideSelect.addEventListener("change", (event) => {
        state.selectedSide = event.target.value;
        state.nextBetAmount = state.startingBet;
        state.activeBet = null;
        state.status = state.isSessionRunning
            ? `Bet side changed to ${state.selectedSide}. Waiting for a new table.`
            : `Bet side changed to ${state.selectedSide}. Press Play to start the session.`;
        renderAll();
    });

    elements.startingBetInput.addEventListener("change", (event) => {
        state.startingBet = sanitizePositiveInteger(event.target.value, state.startingBet);
        elements.startingBetInput.value = String(state.startingBet);
        applyStartingBetChanges(true);
        renderAll();
    });

    elements.stopLossSelect.addEventListener("change", (event) => {
        state.selectedStopLoss = Number(event.target.value);
        if (state.nextBetAmount > state.selectedStopLoss) {
            state.nextBetAmount = state.startingBet;
            state.activeBet = null;
            state.status = `Stop loss updated to ${currency(state.selectedStopLoss)}. Progression reset.`;
        }
        renderAll();
    });

    elements.tableTimerInput.addEventListener("change", (event) => {
        state.tableTimer = sanitizePositiveInteger(event.target.value, state.tableTimer);
        elements.tableTimerInput.value = String(state.tableTimer);
        state.status = state.isSessionRunning
            ? `Table timer updated to ${state.tableTimer}s. New table cycles will use the new timer.`
            : `Table timer updated to ${state.tableTimer}s.`;
        renderAll();
    });

    elements.speedSelect.addEventListener("change", (event) => {
        if (state.isSessionRunning) {
            syncSimClock();
        }
        state.selectedSpeed = Number(event.target.value);
        if (state.isSessionRunning) {
            scheduleNextEvent();
        }
        renderAll();
    });

    elements.warningLevelInput.addEventListener("change", (event) => {
        state.warningLevel = sanitizePositiveInteger(event.target.value, state.warningLevel);
        elements.warningLevelInput.value = String(state.warningLevel);
        renderAll();
    });

    elements.autoContinueToggle.addEventListener("change", (event) => {
        state.autoContinueEnabled = event.target.checked;
        renderAll();
    });

    elements.saveHistoryToggle.addEventListener("change", (event) => {
        state.saveHistoryEnabled = event.target.checked;
        renderHistory();
        renderAnalytics();
        renderSummary();
    });

    elements.toggleSessionButton.addEventListener("click", toggleSession);
    elements.stopButton.addEventListener("click", stopAndResetSimTime);
    elements.clearHistoryButton.addEventListener("click", clearHistory);
    elements.continueButton.addEventListener("click", continueAfterStopLoss);
    elements.haltButton.addEventListener("click", haltFromStopLoss);

    window.addEventListener("resize", () => {
        renderAnalytics();
    });
}

function makeInitialTables(countdown) {
    const safeCountdown = Math.max(1, countdown);
    return Array.from({ length: TABLE_COUNT }, (_, index) => ({
        id: index + 1,
        name: `Table ${index + 1}`,
        result: randomWeightedSide(),
        nextResultSimTime: randomInt(1, safeCountdown),
    }));
}

function toggleSession() {
    if (state.isSessionRunning) {
        pauseSession("Session paused.");
        renderAll();
        return;
    }

    dismissStopLossAlert();
    state.isSessionRunning = true;
    state.lastResumePerf = performance.now();
    state.status = state.activeBet === null
        ? `Session started. Selecting a table for ${currency(state.nextBetAmount)}.`
        : "Session resumed.";

    ensureActiveBet(getCurrentSimSeconds());
    scheduleNextEvent();
    startRenderLoop();
    renderAll();
}

function pauseSession(message) {
    if (state.isSessionRunning) {
        syncSimClock();
    }
    state.isSessionRunning = false;
    state.lastResumePerf = null;
    clearScheduledEvent();
    stopRenderLoop();
    if (message) {
        state.status = message;
    }
}

function stopAndResetSimTime() {
    dismissStopLossAlert();
    pauseSession(null);
    state.activeBet = null;
    state.nextBetAmount = state.startingBet;
    state.nextStreakStep = 1;
    state.currentStreakGroupID = makeID();
    state.storedBetsQueue = [];
    state.simulationReferenceDate = new Date();
    state.simCurrentSeconds = 0;
    state.tables = makeInitialTables(state.tableTimer);
    state.status = "Session stopped. Sim Time reset. Press Play to start again.";
    renderAll();
}

function haltFromStopLoss() {
    dismissStopLossAlert();
    pauseSession(null);
    state.activeBet = null;
    state.nextBetAmount = state.startingBet;
    state.nextStreakStep = 1;
    state.currentStreakGroupID = makeID();
    state.storedBetsQueue = [];
    state.status = "Session stopped from Stop Loss. Press Play to start again.";
    renderAll();
}

function continueAfterStopLoss() {
    dismissStopLossAlert();
    state.isSessionRunning = true;
    state.lastResumePerf = performance.now();
    state.status = `Continuing after stop loss from ${currency(state.startingBet)}.`;
    ensureActiveBet(getCurrentSimSeconds());
    scheduleNextEvent();
    startRenderLoop();
    renderAll();
}

function clearHistory() {
    state.historyEntries = [];
    state.dailyProfits = new Map();
    state.maxLossRecords = new Map();
    state.totalProfit = 0;
    renderAll();
}

function applyStartingBetChanges(resetProgression) {
    populateStopLossOptions();

    if (resetProgression) {
        state.nextBetAmount = state.startingBet;
        state.nextStreakStep = 1;
        state.currentStreakGroupID = makeID();
        state.activeBet = null;
        state.storedBetsQueue = [];
        state.status = state.isSessionRunning
            ? `Starting bet set to ${currency(state.startingBet)}. Waiting for a new table.`
            : `Starting bet set to ${currency(state.startingBet)}. Press Play to start the session.`;
    }
}

function populateStopLossOptions() {
    const options = computeStopLossOptions();
    if (!options.includes(state.selectedStopLoss)) {
        state.selectedStopLoss = options[Math.max(0, DEFAULT_STOP_LOSS_LEVEL - 1)];
    }

    elements.stopLossSelect.innerHTML = options
        .map((amount) => `<option value="${amount}">${currency(amount)}</option>`)
        .join("");
    elements.stopLossSelect.value = String(state.selectedStopLoss);
}

function computeStopLossOptions() {
    return Array.from({ length: STOP_LOSS_LEVELS }, (_, index) => state.startingBet * (2 ** index));
}

function scheduleNextEvent() {
    clearScheduledEvent();
    if (!state.isSessionRunning) {
        return;
    }

    const currentSimSeconds = getCurrentSimSeconds();
    const nextDueTime = state.tables.reduce((minimum, table) => {
        return Math.min(minimum, table.nextResultSimTime);
    }, Number.POSITIVE_INFINITY);

    if (!Number.isFinite(nextDueTime)) {
        return;
    }

    const realDelayMS = Math.max(0, ((nextDueTime - currentSimSeconds) / state.selectedSpeed) * 1000);
    state.eventTimeoutID = window.setTimeout(processDueTables, realDelayMS);
}

function clearScheduledEvent() {
    if (state.eventTimeoutID !== null) {
        window.clearTimeout(state.eventTimeoutID);
        state.eventTimeoutID = null;
    }
}

function processDueTables() {
    if (!state.isSessionRunning) {
        return;
    }

    const nowSimSeconds = getCurrentSimSeconds();
    let lastProcessedTime = state.simCurrentSeconds;
    let processedEvents = 0;

    while (processedEvents < 50000) {
        const dueIndex = nextDueTableIndex(nowSimSeconds);
        if (dueIndex === -1) {
            break;
        }

        const table = state.tables[dueIndex];
        const eventTime = table.nextResultSimTime;
        table.result = randomWeightedSide();
        table.nextResultSimTime = eventTime + state.tableTimer;
        lastProcessedTime = eventTime;

        if (state.activeBet?.tableID === table.id) {
            const previousTableID = table.id;
            const resolution = resolveActiveBet(table.result, eventTime);

            if (!state.isSessionRunning) {
                break;
            }

            if (resolution === "stopLoss") {
                if (state.autoContinueEnabled) {
                    queueNextBaseBet(eventTime, previousTableID);
                }
            } else {
                ensureActiveBet(eventTime, previousTableID);
            }
        }

        processedEvents += 1;
    }

    if (state.isSessionRunning) {
        state.simCurrentSeconds = Math.max(nowSimSeconds, lastProcessedTime);
        state.lastResumePerf = performance.now();
    } else {
        state.simCurrentSeconds = Math.max(state.simCurrentSeconds, lastProcessedTime);
    }

    if (state.isSessionRunning) {
        if (state.autoContinueEnabled || state.stopLossAlert === null) {
            ensureActiveBet(state.simCurrentSeconds);
        }
        scheduleNextEvent();
    }

    renderFromSimulationStep();
}

function nextDueTableIndex(targetSimSeconds) {
    let bestIndex = -1;
    let bestTime = Number.POSITIVE_INFINITY;

    state.tables.forEach((table, index) => {
        if (table.nextResultSimTime <= targetSimSeconds && table.nextResultSimTime < bestTime) {
            bestIndex = index;
            bestTime = table.nextResultSimTime;
        }
    });

    return bestIndex;
}

function resolveActiveBet(result, eventSimSeconds) {
    const activeBet = state.activeBet;
    if (!activeBet) {
        return "none";
    }

    const eventDate = simulationDateFor(eventSimSeconds);

    if (result === activeBet.side) {
        const profitChange = result === "Tie" ? activeBet.amount * 8 : activeBet.amount;
        state.totalProfit += profitChange;
        updateDailyProfit(eventDate, profitChange);

        if (state.saveHistoryEnabled) {
            appendHistory(activeBet, result, "Win", eventDate);
        }

        if (state.strategy === "mod" && state.storedBetsQueue.length > 0) {
            state.nextBetAmount = state.storedBetsQueue.shift();
            state.nextStreakStep = 1;
            state.currentStreakGroupID = makeID();
            state.status = `Win on Table ${activeBet.tableID}. Playing queued bet ${currency(state.nextBetAmount)}.`;
        } else {
            state.nextBetAmount = state.startingBet;
            state.nextStreakStep = 1;
            state.currentStreakGroupID = makeID();
            state.status = `Win on Table ${activeBet.tableID}. Resetting to ${currency(state.startingBet)}.`;
        }

        state.activeBet = null;
        return "win";
    }

    if (result === "Tie") {
        updateDailyProfit(eventDate, 0);

        if (state.saveHistoryEnabled) {
            appendHistory(activeBet, result, "Push", eventDate);
        }

        state.status = `Tie on Table ${activeBet.tableID}. Bet pushed.`;
        state.activeBet = null;
        return "push";
    }

    state.totalProfit -= activeBet.amount;
    updateDailyProfit(eventDate, -activeBet.amount);

    if (activeBet.amount >= state.selectedStopLoss) {
        incrementMaxLoss();

        if (state.saveHistoryEnabled) {
            appendHistory(activeBet, result, "Stop", eventDate);
        }

        state.nextBetAmount = state.startingBet;
        state.nextStreakStep = 1;
        state.currentStreakGroupID = makeID();
        state.storedBetsQueue = [];
        state.activeBet = null;

        const baseMessage = `Loss on Table ${activeBet.tableID} at ${currency(activeBet.amount)}.`;
        presentStopLossAlert(
            state.autoContinueEnabled
                ? `${baseMessage} Auto Continue placed the next base bet.`
                : `${baseMessage} Continue to start again from ${currency(state.startingBet)}.`,
            state.autoContinueEnabled,
        );

        state.status = state.autoContinueEnabled
            ? `${baseMessage} Auto continuing from ${currency(state.startingBet)}.`
            : `${baseMessage} Waiting for your decision.`;

        if (!state.autoContinueEnabled) {
            state.isSessionRunning = false;
            state.simCurrentSeconds = eventSimSeconds;
            state.lastResumePerf = null;
            clearScheduledEvent();
            stopRenderLoop();
        }

        return "stopLoss";
    }

    if (state.saveHistoryEnabled) {
        appendHistory(activeBet, result, "Loss", eventDate);
    }

    const doubledBet = Math.min(activeBet.amount * 2, state.selectedStopLoss);

    if (state.strategy === "mod" && activeBet.streakStep === state.warningLevel) {
        state.storedBetsQueue.push(doubledBet);
        state.nextBetAmount = state.startingBet;
        state.nextStreakStep = 1;
        state.currentStreakGroupID = makeID();
        state.status = `Warning hit on Table ${activeBet.tableID}. Stored ${currency(doubledBet)}. Resetting to ${currency(state.startingBet)}.`;
    } else {
        state.nextBetAmount = doubledBet;
        state.nextStreakStep = activeBet.streakStep + 1;
        state.status = `Loss on Table ${activeBet.tableID}. Next bet is ${currency(doubledBet)} on ${state.selectedSide}.`;
    }

    state.activeBet = null;
    return "loss";
}

function updateDailyProfit(eventDate, profitChange) {
    const key = dayKey(eventDate);
    const record = state.dailyProfits.get(key) ?? {
        key,
        day: startOfDay(eventDate),
        profit: 0,
        handsPlayed: 0,
    };

    record.profit += profitChange;
    record.handsPlayed += 1;
    state.dailyProfits.set(key, record);
}

function incrementMaxLoss() {
    const strategyName = STRATEGIES[state.strategy];
    const warningLevel = state.strategy === "mod" ? state.warningLevel : 0;
    const key = `${strategyName}|${warningLevel}|${state.selectedStopLoss}`;
    const record = state.maxLossRecords.get(key) ?? {
        key,
        strategyName,
        stopLossAmount: state.selectedStopLoss,
        warningLevel,
        maxLossCount: 0,
    };

    record.maxLossCount += 1;
    state.maxLossRecords.set(key, record);
}

function appendHistory(activeBet, result, outcome, timestamp) {
    state.historyEntries.unshift({
        id: makeID(),
        timestamp,
        tableID: activeBet.tableID,
        betAmount: activeBet.amount,
        betSide: activeBet.side,
        result,
        outcome,
        streakStep: activeBet.streakStep,
        streakGroupID: activeBet.streakGroupID,
    });
}

function randomEligibleTable(afterSimSeconds, excludingTableID = null) {
    const eligibleTables = state.tables.filter((table) => {
        if (table.nextResultSimTime <= afterSimSeconds) {
            return false;
        }

        if (excludingTableID !== null && table.id === excludingTableID) {
            return false;
        }

        return true;
    });

    if (eligibleTables.length === 0) {
        return null;
    }

    return eligibleTables[randomInt(0, eligibleTables.length - 1)];
}

function setActiveBet(table, updateStatus) {
    state.activeBet = {
        tableID: table.id,
        amount: state.nextBetAmount,
        side: state.selectedSide,
        streakStep: state.nextStreakStep,
        streakGroupID: state.currentStreakGroupID,
    };

    if (updateStatus) {
        state.status = `Betting ${currency(state.nextBetAmount)} on ${state.selectedSide} at Table ${table.id} • Streak ${state.nextStreakStep}.`;
    }
}

function ensureActiveBet(simSeconds, previousTableID = null) {
    if (state.activeBet) {
        const activeTable = state.tables.find((table) => table.id === state.activeBet.tableID);
        if (activeTable && activeTable.nextResultSimTime <= simSeconds) {
            state.activeBet = null;
        }
    }

    if (state.activeBet !== null) {
        return;
    }

    const nextTable = randomEligibleTable(simSeconds, previousTableID);
    if (!nextTable) {
        return;
    }

    setActiveBet(nextTable, true);
}

function queueNextBaseBet(simSeconds, previousTableID = null) {
    if (state.activeBet !== null) {
        return;
    }

    const nextTable = randomEligibleTable(simSeconds, previousTableID);
    if (!nextTable) {
        return;
    }

    setActiveBet(nextTable, false);
}

function presentStopLossAlert(message, autoContinued) {
    dismissStopLossAlert();
    state.stopLossAlert = { message, autoContinued };

    if (autoContinued) {
        state.stopLossDismissTimeout = window.setTimeout(() => {
            dismissStopLossAlert();
            renderAll();
        }, 2500);
    }
}

function dismissStopLossAlert() {
    if (state.stopLossDismissTimeout !== null) {
        window.clearTimeout(state.stopLossDismissTimeout);
        state.stopLossDismissTimeout = null;
    }
    state.stopLossAlert = null;
}

function startRenderLoop() {
    if (state.renderFrameID !== null) {
        return;
    }

    const loop = () => {
        renderDynamic();
        if (state.isSessionRunning) {
            state.renderFrameID = window.requestAnimationFrame(loop);
        } else {
            state.renderFrameID = null;
        }
    };

    state.renderFrameID = window.requestAnimationFrame(loop);
}

function stopRenderLoop() {
    if (state.renderFrameID !== null) {
        window.cancelAnimationFrame(state.renderFrameID);
        state.renderFrameID = null;
    }
}

function renderAll() {
    renderTabs();
    renderSummary();
    renderControls();
    renderTables();
    renderHistory();
    renderAnalytics();
    renderStopLossModal();
}

function renderDynamic() {
    renderSummary();
    renderTables();
    renderStopLossModal();

    if (state.activeTab === "history") {
        renderHistoryHeader();
    }
}

function renderFromSimulationStep() {
    renderSummary();
    renderTables();
    renderStopLossModal();

    if (state.activeTab === "history") {
        renderHistory();
    }

    if (state.activeTab === "analytics") {
        renderAnalytics();
    }
}

function renderTabs() {
    elements.tabs.forEach((tab) => {
        tab.classList.toggle("is-active", tab.dataset.tabTarget === state.activeTab);
    });

    elements.panels.forEach((panel) => {
        panel.classList.toggle("is-active", panel.dataset.tabPanel === state.activeTab);
    });
}

function renderSummary() {
    elements.strategyLabel.textContent = STRATEGIES[state.strategy];
    elements.currentBetLabel.textContent = currency(state.activeBet?.amount ?? state.nextBetAmount);
    elements.activeTableLabel.textContent = state.activeBet ? `T${state.activeBet.tableID}` : "--";
    elements.queuedLabel.textContent = String(state.strategy === "mod" ? state.storedBetsQueue.length : 0);
    elements.speedLabel.textContent = SPEED_LABELS[state.selectedSpeed];
    elements.totalProfitLabel.textContent = currency(state.totalProfit);
    elements.totalProfitLabel.style.color = state.totalProfit >= 0 ? "#7df0a7" : "#ff8f8f";
    elements.simulationStatus.textContent = state.status;
    elements.simTimeLabel.textContent = formatSimElapsed(getCurrentSimSeconds());
    elements.toggleSessionButton.textContent = state.isSessionRunning ? "Pause" : "Play";
}

function renderControls() {
    elements.strategySelect.value = state.strategy;
    elements.sideSelect.value = state.selectedSide;
    elements.startingBetInput.value = String(state.startingBet);
    elements.stopLossSelect.value = String(state.selectedStopLoss);
    elements.tableTimerInput.value = String(state.tableTimer);
    elements.speedSelect.value = String(state.selectedSpeed);
    elements.warningLevelInput.value = String(state.warningLevel);
    elements.autoContinueToggle.checked = state.autoContinueEnabled;
    elements.saveHistoryToggle.checked = state.saveHistoryEnabled;
    elements.warningField.hidden = state.strategy !== "mod";
}

function renderTables() {
    const currentSimSeconds = getCurrentSimSeconds();

    elements.tableGrid.innerHTML = state.tables
        .map((table) => {
            const isActive = state.activeBet?.tableID === table.id;
            const secondsRemaining = Math.max(0, Math.ceil(table.nextResultSimTime - currentSimSeconds));
            const resultLabel = table.result === "Tie" ? "TIE" : table.result.charAt(0);

            return `
                <article class="table-tile ${isActive ? "is-active" : ""}">
                    <div class="table-head">
                        <span class="table-name">T${table.id}</span>
                        ${isActive ? '<span class="coin-dot" aria-hidden="true"></span>' : ""}
                    </div>
                    <div class="table-result table-result--${table.result}">${resultLabel}</div>
                    <div class="table-foot">
                        <span class="table-timer">${secondsRemaining}s</span>
                        ${isActive ? `<span class="bet-chip">${currency(state.activeBet.amount)}</span>` : ""}
                    </div>
                </article>
            `;
        })
        .join("");
}

function renderHistory() {
    renderHistoryHeader();

    if (state.saveHistoryEnabled) {
        elements.historyListTitle.textContent = "Detailed Rounds";
        if (state.historyEntries.length === 0) {
            elements.historyList.innerHTML = '<div class="empty-state">No detailed history yet. Turn on Save Detailed History and play a session.</div>';
            return;
        }

        const entries = state.historyEntries.slice(0, 250);
        elements.historyList.innerHTML = entries
            .map((entry) => {
                const isStopLoss = entry.outcome === "Stop";
                return `
                    <article class="history-item ${isStopLoss ? "is-stop-loss" : ""}">
                        <div class="history-topline">
                            <span class="history-badge history-badge--${entry.outcome}">${entry.outcome}</span>
                            <span>${timestampFormatter.format(entry.timestamp)}</span>
                        </div>
                        <h4>Table ${entry.tableID} • ${currency(entry.betAmount)} on ${entry.betSide}</h4>
                        <div class="history-meta">
                            <span>Result: ${entry.result}</span>
                            <span>Streak ${entry.streakStep}</span>
                        </div>
                    </article>
                `;
            })
            .join("");
        return;
    }

    elements.historyListTitle.textContent = "Daily Earnings";
    const records = Array.from(state.dailyProfits.values()).sort((a, b) => b.day - a.day);

    if (records.length === 0) {
        elements.historyList.innerHTML = '<div class="empty-state">No daily data yet. Start a session to populate the summary.</div>';
        return;
    }

    elements.historyList.innerHTML = records
        .map((record) => {
            return `
                <article class="history-item">
                    <div class="history-topline">
                        <strong>${fullDayFormatter.format(record.day)}</strong>
                        <span>${currency(record.profit)}</span>
                    </div>
                    <div class="history-meta">
                        <span>${record.handsPlayed} hands played</span>
                        <span>${record.profit >= 0 ? "Up" : "Down"} for the day</span>
                    </div>
                </article>
            `;
        })
        .join("");
}

function renderHistoryHeader() {
    const currentRecord = state.dailyProfits.get(dayKey(simulationDateFor(getCurrentSimSeconds())));
    const handsPlayed = currentRecord?.handsPlayed ?? 0;
    const currentProfit = currentRecord?.profit ?? 0;

    elements.historyModeLabel.textContent = state.saveHistoryEnabled ? "Detailed Round History" : "Daily Summary";
    elements.historySummaryCopy.textContent = state.saveHistoryEnabled
        ? `${state.historyEntries.length} stored rounds in memory. Showing the latest 250 entries.`
        : `${state.dailyProfits.size} simulated days currently stored in memory.`;
    elements.handsTodayLabel.textContent = String(handsPlayed);
    elements.historyProfitCopy.textContent = `Current day profit: ${currency(currentProfit)}`;
}

function renderAnalytics() {
    renderMaxLossList();
    renderResultDistribution();
    renderProfitTrend();
}

function renderMaxLossList() {
    const records = Array.from(state.maxLossRecords.values())
        .filter((record) => record.maxLossCount > 0)
        .sort((a, b) => {
            if (a.strategyName !== b.strategyName) {
                return a.strategyName.localeCompare(b.strategyName);
            }
            if (a.warningLevel !== b.warningLevel) {
                return a.warningLevel - b.warningLevel;
            }
            return a.stopLossAmount - b.stopLossAmount;
        });

    if (records.length === 0) {
        elements.maxLossList.innerHTML = '<div class="empty-state">No stop-loss hits recorded yet.</div>';
        return;
    }

    elements.maxLossList.innerHTML = records
        .map((record) => {
            const warningText = record.strategyName === STRATEGIES.mod
                ? ` • Warning ${record.warningLevel}`
                : "";

            return `
                <article class="max-loss-item">
                    <div class="max-loss-meta">
                        <h4>${record.strategyName}${warningText}</h4>
                        <strong>${record.maxLossCount}</strong>
                    </div>
                    <p>Stop Loss: ${currency(record.stopLossAmount)}</p>
                </article>
            `;
        })
        .join("");
}

function renderResultDistribution() {
    if (!state.saveHistoryEnabled || state.historyEntries.length === 0) {
        drawEmptyChart(elements.resultPieChart, "No detailed history");
        return;
    }

    const counts = {
        Banker: 0,
        Player: 0,
        Tie: 0,
    };

    state.historyEntries.forEach((entry) => {
        counts[entry.result] += 1;
    });

    drawPieChart(elements.resultPieChart, counts);
}

function renderProfitTrend() {
    if (state.saveHistoryEnabled) {
        elements.trendTitle.textContent = "Cumulative Profit / Loss";
        const points = [{ label: "0", value: 0 }];
        let currentProfit = 0;

        [...state.historyEntries].reverse().forEach((entry, index) => {
            if (entry.outcome === "Win") {
                currentProfit += entry.betSide === "Tie" ? entry.betAmount * 8 : entry.betAmount;
            } else if (entry.outcome === "Loss" || entry.outcome === "Stop") {
                currentProfit -= entry.betAmount;
            }

            points.push({ label: String(index + 1), value: currentProfit });
        });

        if (points.length <= 1) {
            drawEmptyChart(elements.profitLineChart, "No detailed profit data");
            return;
        }

        drawLineChart(elements.profitLineChart, points);
        return;
    }

    elements.trendTitle.textContent = "Cumulative Daily Profit";
    const records = Array.from(state.dailyProfits.values()).sort((a, b) => a.day - b.day);
    let runningProfit = 0;
    const points = records.map((record) => {
        runningProfit += record.profit;
        return {
            label: `${record.day.getMonth() + 1}/${record.day.getDate()}`,
            value: runningProfit,
        };
    });

    if (points.length === 0) {
        drawEmptyChart(elements.profitLineChart, "No daily profit data");
        return;
    }

    drawLineChart(elements.profitLineChart, points);
}

function renderStopLossModal() {
    const alert = state.stopLossAlert;
    const showModal = alert && !alert.autoContinued;

    elements.stopLossModal.hidden = !showModal;
    elements.stopLossMessage.textContent = alert?.message ?? "";
}

function drawPieChart(canvas, counts) {
    const { ctx, width, height } = prepareCanvas(canvas);
    ctx.clearRect(0, 0, width, height);

    const total = Object.values(counts).reduce((sum, value) => sum + value, 0);
    if (total === 0) {
        drawEmptyChart(canvas, "No results yet");
        return;
    }

    const centerX = width / 2;
    const centerY = height / 2;
    const radius = Math.min(width, height) * 0.32;
    const innerRadius = radius * 0.58;
    let startAngle = -Math.PI / 2;

    Object.entries(counts).forEach(([side, count]) => {
        if (count === 0) {
            return;
        }

        const sliceAngle = (count / total) * Math.PI * 2;
        ctx.beginPath();
        ctx.moveTo(centerX, centerY);
        ctx.arc(centerX, centerY, radius, startAngle, startAngle + sliceAngle);
        ctx.closePath();
        ctx.fillStyle = RESULT_COLORS[side];
        ctx.fill();

        startAngle += sliceAngle;
    });

    ctx.beginPath();
    ctx.fillStyle = "rgba(6, 18, 13, 0.95)";
    ctx.arc(centerX, centerY, innerRadius, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "#f5efd8";
    ctx.font = "700 16px Georgia";
    ctx.textAlign = "center";
    ctx.fillText(`${total}`, centerX, centerY - 4);
    ctx.fillStyle = "rgba(245, 239, 216, 0.68)";
    ctx.font = "13px Georgia";
    ctx.fillText("results", centerX, centerY + 18);
}

function drawLineChart(canvas, points) {
    const { ctx, width, height } = prepareCanvas(canvas);
    ctx.clearRect(0, 0, width, height);

    if (points.length === 0) {
        drawEmptyChart(canvas, "No trend data");
        return;
    }

    const padding = { top: 28, right: 22, bottom: 36, left: 52 };
    const chartWidth = width - padding.left - padding.right;
    const chartHeight = height - padding.top - padding.bottom;
    const values = points.map((point) => point.value);
    const minValue = Math.min(...values, 0);
    const maxValue = Math.max(...values, 0);
    const span = Math.max(1, maxValue - minValue);

    ctx.strokeStyle = "rgba(255, 255, 255, 0.08)";
    ctx.lineWidth = 1;
    for (let line = 0; line < 4; line += 1) {
        const y = padding.top + (chartHeight / 3) * line;
        ctx.beginPath();
        ctx.moveTo(padding.left, y);
        ctx.lineTo(width - padding.right, y);
        ctx.stroke();
    }

    ctx.strokeStyle = "#5ea2ff";
    ctx.lineWidth = 3;
    ctx.beginPath();

    points.forEach((point, index) => {
        const x = padding.left + (chartWidth * index) / Math.max(1, points.length - 1);
        const normalized = (point.value - minValue) / span;
        const y = padding.top + chartHeight - normalized * chartHeight;
        if (index === 0) {
            ctx.moveTo(x, y);
        } else {
            ctx.lineTo(x, y);
        }
    });

    ctx.stroke();

    ctx.fillStyle = "rgba(94, 162, 255, 0.16)";
    ctx.lineTo(width - padding.right, height - padding.bottom);
    ctx.lineTo(padding.left, height - padding.bottom);
    ctx.closePath();
    ctx.fill();

    ctx.fillStyle = "rgba(245, 239, 216, 0.70)";
    ctx.font = "12px Georgia";
    ctx.textAlign = "left";
    ctx.fillText(currency(maxValue), 10, padding.top + 6);
    ctx.fillText(currency(minValue), 10, height - padding.bottom);

    ctx.textAlign = "right";
    ctx.fillText(points[0].label, padding.left, height - 10);
    ctx.fillText(points[points.length - 1].label, width - padding.right, height - 10);
}

function drawEmptyChart(canvas, message) {
    const { ctx, width, height } = prepareCanvas(canvas);
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = "rgba(255, 255, 255, 0.04)";
    ctx.fillRect(0, 0, width, height);
    ctx.fillStyle = "rgba(245, 239, 216, 0.70)";
    ctx.textAlign = "center";
    ctx.font = "16px Georgia";
    ctx.fillText(message, width / 2, height / 2);
}

function prepareCanvas(canvas) {
    const dpr = window.devicePixelRatio || 1;
    const width = canvas.clientWidth || canvas.width;
    const height = canvas.clientHeight || canvas.height;

    canvas.width = Math.max(1, Math.floor(width * dpr));
    canvas.height = Math.max(1, Math.floor(height * dpr));

    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    return { ctx, width, height };
}

function getCurrentSimSeconds() {
    if (!state.isSessionRunning || state.lastResumePerf === null) {
        return state.simCurrentSeconds;
    }

    const elapsedRealSeconds = (performance.now() - state.lastResumePerf) / 1000;
    return state.simCurrentSeconds + elapsedRealSeconds * state.selectedSpeed;
}

function syncSimClock() {
    state.simCurrentSeconds = getCurrentSimSeconds();
    state.lastResumePerf = performance.now();
}

function simulationDateFor(simSeconds) {
    return new Date(state.simulationReferenceDate.getTime() + simSeconds * 1000);
}

function formatSimElapsed(totalSeconds) {
    const safeSeconds = Math.max(0, Math.floor(totalSeconds));
    const days = Math.floor(safeSeconds / 86400);
    const hours = Math.floor((safeSeconds % 86400) / 3600);
    const minutes = Math.floor((safeSeconds % 3600) / 60);
    return `${days}d ${hours}h ${minutes}m`;
}

function currency(amount) {
    return pesoFormatter.format(amount);
}

function randomWeightedSide() {
    const randomValue = Math.random();
    if (randomValue < 0.4586) {
        return "Banker";
    }
    if (randomValue < 0.4586 + 0.4462) {
        return "Player";
    }
    return "Tie";
}

function randomInt(minimum, maximum) {
    return Math.floor(Math.random() * (maximum - minimum + 1)) + minimum;
}

function sanitizePositiveInteger(rawValue, fallback) {
    const parsed = Number.parseInt(rawValue, 10);
    if (!Number.isFinite(parsed) || parsed < 1) {
        return Math.max(1, fallback);
    }
    return parsed;
}

function dayKey(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
}

function startOfDay(date) {
    return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function makeID() {
    if (window.crypto?.randomUUID) {
        return window.crypto.randomUUID();
    }
    return `id-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}
