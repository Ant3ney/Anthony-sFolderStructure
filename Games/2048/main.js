(() => {
  const PREF_KEY = "sf2048_high_contrast";
  const CONTROL_PROFILE_KEY = "sf2048_control_profile";
  const SESSION_STORAGE_KEY = "sf2048_game_session_v2";
  const SESSION_STORAGE_VERSION = 2;
  const LEGACY_SESSION_STORAGE_KEYS = ["sf2048_game_session", "sf2048_game_state"];
  const engine = window.Game2048;
  if (!engine) {
    return;
  }

  const {
    BOARD_SIZE,
    createInitialState,
    deserialize,
    executeMove,
    serialize,
    undo,
  } = engine;

  const gameBoard = document.getElementById("gameBoard");
  const boardCells = document.getElementById("boardCells");
  const boardTiles = document.getElementById("boardTiles");
  const statusText = document.getElementById("statusText");
  const ariaStatus = document.getElementById("ariaStatus");
  const scoreValue = document.getElementById("scoreValue");
  const moveValue = document.getElementById("moveValue");
  const highScoreValue = document.getElementById("highScoreValue");
  const timerValue = document.getElementById("timerValue");
  const newGameButton = document.getElementById("newGameButton");
  const undoButton = document.getElementById("undoButton");
  const pauseButton = document.getElementById("pauseButton");
  const contrastToggle = document.getElementById("contrastToggle");
  const directionButtons = document.querySelectorAll("[data-dir]");

  const DEFAULT_INPUT_PROFILE = {
    transitionLockMs: 210,
    noMoveLockMs: 120,
    keys: {
      ArrowUp: "up",
      ArrowDown: "down",
      ArrowLeft: "left",
      ArrowRight: "right",
      w: "up",
      s: "down",
      a: "left",
      d: "right",
      W: "up",
      S: "down",
      A: "left",
      D: "right",
    },
    swipe: {
      enabled: true,
      minDistance: 24,
      axisBias: 1.3,
      allowMouse: true,
      allowTouch: true,
    },
    buttons: {
      enabled: true,
    },
  };

  const stateSeed = (typeof crypto !== "undefined" && crypto.getRandomValues)
    ? crypto.getRandomValues(new Uint32Array(1))[0]
    : Date.now();
  const TIMER_TICK_MS = 1000;

  const boardCellsByIndex = [];
  const defaultStatusMessage = "Use directional controls to move tiles.";
  const textColorByValue = {
    2: "var(--tile-text-dark)",
    4: "var(--tile-text-dark)",
  };

  const inputProfile = parseInputProfile();
  const transitionLockMs = deriveTransitionLockMs();
  const swipeState = {
    active: false,
    pointerId: null,
    startX: 0,
    startY: 0,
    handled: false,
    direction: null,
  };
  const inputLock = {
    active: false,
    timer: null,
  };
  const pressedKeys = new Set();
  let state = createInitialState(stateSeed);
  let bestScore = 0;
  let elapsedMs = 0;
  let isPaused = false;
  let timerHandle = null;
  let lastTickAt = null;

  function clampNonNegativeInteger(value, fallback) {
    const asNumber = Number(value);
    const asInteger = Number.isFinite(asNumber) ? Math.trunc(asNumber) : NaN;
    return Number.isFinite(asInteger) && asInteger >= 0 ? asInteger : fallback;
  }

  function formatElapsed(milliseconds) {
    const totalSeconds = Math.floor(clampNonNegativeInteger(milliseconds, 0) / 1000);
    const minutes = Math.floor(totalSeconds / 60);
    const seconds = totalSeconds % 60;
    return `${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`;
  }

  function readStorageJSON(key) {
    try {
      const stored = localStorage.getItem(key);
      if (!stored) {
        return null;
      }
      return JSON.parse(stored);
    } catch (error) {
      return null;
    }
  }

  function writeStorageJSON(key, value) {
    try {
      localStorage.setItem(key, JSON.stringify(value));
    } catch (error) {
      // no-op
    }
  }

  function safeDeserializeState(payload) {
    try {
      return deserialize(payload);
    } catch (error) {
      return null;
    }
  }

  function normalizeStoragePayload(payload) {
    if (!payload || typeof payload !== "object") {
      return null;
    }

    const schemaVersion = clampNonNegativeInteger(payload.schemaVersion, 0);
    if (schemaVersion > SESSION_STORAGE_VERSION) {
      return null;
    }

    const candidateState = payload.state || payload.gameState || payload;
    const restoredState = safeDeserializeState(candidateState);
    if (!restoredState) {
      return null;
    }

    return {
      state: restoredState,
      bestScore: clampNonNegativeInteger(
        payload.bestScore !== undefined
          ? payload.bestScore
          : payload.highScore,
        restoredState.score,
      ),
      elapsedMs: clampNonNegativeInteger(
        payload.elapsedMs !== undefined ? payload.elapsedMs : payload.elapsed,
        0,
      ),
      isPaused: payload.isPaused || payload.paused || false,
      lastSavedAt: clampNonNegativeInteger(payload.lastSavedAt, 0),
    };
  }

  function loadPersistedSession() {
    const primaryPayload = readStorageJSON(SESSION_STORAGE_KEY);
    if (primaryPayload) {
      const normalized = normalizeStoragePayload(primaryPayload);
      if (normalized) {
        return normalized;
      }
    }

    for (let i = 0; i < LEGACY_SESSION_STORAGE_KEYS.length; i += 1) {
      const key = LEGACY_SESSION_STORAGE_KEYS[i];
      const raw = readStorageJSON(key);
      const normalized = raw ? normalizeStoragePayload(raw) : null;
      if (normalized) {
        return normalized;
      }
    }

    return null;
  }

  function commitElapsed(now = Date.now()) {
    if (!lastTickAt || isPaused || state.over) {
      return;
    }
    const delta = now - lastTickAt;
    if (Number.isFinite(delta) && delta > 0) {
      elapsedMs += delta;
    }
    lastTickAt = now;
  }

  function stopTimer() {
    const wasPaused = isPaused;
    isPaused = false;
    if (timerHandle) {
      clearInterval(timerHandle);
      timerHandle = null;
    }
    commitElapsed();
    isPaused = wasPaused;
    lastTickAt = null;
  }

  function tickTimer() {
    commitElapsed();
    if (!timerHandle || isPaused || state.over) {
      stopTimer();
      return;
    }
    timerValue.textContent = formatElapsed(elapsedMs);
    persistSession();
  }

  function startTimer() {
    if (isPaused || state.over || timerHandle) {
      return;
    }
    lastTickAt = Date.now();
    timerHandle = setInterval(tickTimer, TIMER_TICK_MS);
  }

  function persistSession() {
    commitElapsed();
    const serializedState = serialize(state);
    if (typeof serializedState !== "string") {
      return;
    }
    let statePayload;
    try {
      statePayload = JSON.parse(serializedState);
    } catch (error) {
      return;
    }
    if (state.score > bestScore) {
      bestScore = state.score;
    }
    writeStorageJSON(SESSION_STORAGE_KEY, {
      schemaVersion: SESSION_STORAGE_VERSION,
      state: statePayload,
      bestScore,
      elapsedMs,
      isPaused,
      lastSavedAt: Date.now(),
    });
  }

  function cloneProfile(profile) {
    try {
      return JSON.parse(JSON.stringify(profile));
    } catch (error) {
      return {
        transitionLockMs: profile.transitionLockMs,
        noMoveLockMs: profile.noMoveLockMs,
        keys: Object.assign({}, profile.keys),
        swipe: Object.assign({}, profile.swipe),
        buttons: Object.assign({}, profile.buttons),
      };
    }
  }

  function mergeInputProfile(base, incoming) {
    if (!incoming || typeof incoming !== "object" || Array.isArray(incoming)) {
      return base;
    }
    Object.keys(incoming).forEach((key) => {
      const value = incoming[key];
      if (value === undefined || value === null) {
        return;
      }
      if (
        typeof value === "object"
        && !Array.isArray(value)
        && typeof base[key] === "object"
        && !Array.isArray(base[key])
      ) {
        mergeInputProfile(base[key], value);
        return;
      }
      base[key] = value;
    });
    return base;
  }

  function normalizePositiveInteger(value, fallback) {
    const n = Number(value);
    const asInt = Number.isFinite(n) ? Math.trunc(n) : NaN;
    if (!Number.isFinite(asInt) || asInt < 0) {
      return fallback;
    }
    return asInt;
  }

  function normalizeInputProfile(profile) {
    if (!profile || typeof profile !== "object") {
      return cloneProfile(DEFAULT_INPUT_PROFILE);
    }

    profile.transitionLockMs = normalizePositiveInteger(profile.transitionLockMs, DEFAULT_INPUT_PROFILE.transitionLockMs);
    profile.noMoveLockMs = normalizePositiveInteger(profile.noMoveLockMs, DEFAULT_INPUT_PROFILE.noMoveLockMs);
    profile.keys = profile.keys && typeof profile.keys === "object" && !Array.isArray(profile.keys)
      ? profile.keys
      : cloneProfile(DEFAULT_INPUT_PROFILE.keys);
    profile.swipe = profile.swipe && typeof profile.swipe === "object" && !Array.isArray(profile.swipe)
      ? profile.swipe
      : cloneProfile(DEFAULT_INPUT_PROFILE.swipe);
    profile.swipe.enabled = profile.swipe.enabled !== false;
    profile.swipe.minDistance = normalizePositiveInteger(profile.swipe.minDistance, DEFAULT_INPUT_PROFILE.swipe.minDistance);
    profile.swipe.axisBias = Number.isFinite(Number(profile.swipe.axisBias)) && Number(profile.swipe.axisBias) > 0
      ? Number(profile.swipe.axisBias)
      : DEFAULT_INPUT_PROFILE.swipe.axisBias;
    profile.swipe.allowMouse = profile.swipe.allowMouse !== false;
    profile.swipe.allowTouch = profile.swipe.allowTouch !== false;
    profile.buttons = profile.buttons && typeof profile.buttons === "object" && !Array.isArray(profile.buttons)
      ? profile.buttons
      : cloneProfile(DEFAULT_INPUT_PROFILE.buttons);
    profile.buttons.enabled = profile.buttons.enabled !== false;

    return profile;
  }

  function parseInputProfile() {
    const merged = cloneProfile(DEFAULT_INPUT_PROFILE);
    let stored;
    try {
      stored = JSON.parse(localStorage.getItem(CONTROL_PROFILE_KEY) || "{}");
    } catch (error) {
      stored = {};
    }
    const mergedWithStorage = mergeInputProfile(merged, stored);
    return normalizeInputProfile(mergedWithStorage);
  }

  function parseDurationMs(value, fallbackMs) {
    if (typeof value !== "string") {
      return fallbackMs;
    }
    const match = value.trim().match(/^([0-9]*\.?[0-9]+)\s*(ms|s)$/i);
    if (!match) {
      return fallbackMs;
    }
    const magnitude = Number(match[1]);
    if (!Number.isFinite(magnitude)) {
      return fallbackMs;
    }
    return match[2].toLowerCase() === "s" ? magnitude * 1000 : magnitude;
  }

  function deriveTransitionLockMs() {
    const fallback = DEFAULT_INPUT_PROFILE.transitionLockMs;
    if (!gameBoard || !document || !window || !window.getComputedStyle) {
      return fallback + 25;
    }
    const computed = getComputedStyle(document.documentElement).getPropertyValue("--motion-medium");
    const parsed = parseDurationMs(computed, fallback);
    return Math.max(1, Math.ceil(parsed + 25));
  }

  function isPointerAllowed(pointerType) {
    if (pointerType === "mouse") {
      return inputProfile.swipe.allowMouse;
    }
    if (pointerType === "touch") {
      return inputProfile.swipe.allowTouch;
    }
    return true;
  }

  function clearSwipeState() {
    swipeState.active = false;
    swipeState.pointerId = null;
    swipeState.startX = 0;
    swipeState.startY = 0;
    swipeState.handled = false;
    swipeState.direction = null;
  }

  function clearInputLock() {
    inputLock.active = false;
    if (inputLock.timer) {
      clearTimeout(inputLock.timer);
      inputLock.timer = null;
    }
  }

  function beginInputLock(durationMs) {
    const lockMs = normalizePositiveInteger(durationMs, 0);
    clearInputLock();
    if (lockMs <= 0) {
      return;
    }
    inputLock.active = true;
    inputLock.timer = setTimeout(() => {
      inputLock.active = false;
      inputLock.timer = null;
    }, lockMs);
  }

  function resetControlState() {
    clearInputLock();
    clearSwipeState();
    pressedKeys.clear();
  }

  function setStatus(message) {
    statusText.textContent = message;
    ariaStatus.textContent = message;
  }

  function mapDirectionFromKey(key) {
    const direct = inputProfile.keys[key];
    if (direct) {
      return direct;
    }
    const lower = String(key).toLowerCase();
    const upper = String(key).toUpperCase();
    return inputProfile.keys[lower] || inputProfile.keys[upper];
  }

  function getSwipeDirection(deltaX, deltaY) {
    const absX = Math.abs(deltaX);
    const absY = Math.abs(deltaY);
    const maxDelta = Math.max(absX, absY);
    if (maxDelta < inputProfile.swipe.minDistance) {
      return null;
    }
    if (absX >= absY * inputProfile.swipe.axisBias) {
      return deltaX > 0 ? "right" : "left";
    }
    if (absY >= absX * inputProfile.swipe.axisBias) {
      return deltaY > 0 ? "down" : "up";
    }
    return null;
  }

  function readHighContrastPreference() {
    try {
      return localStorage.getItem(PREF_KEY) === "on";
    } catch (error) {
      return false;
    }
  }

  function writeHighContrastPreference(enabled) {
    try {
      localStorage.setItem(PREF_KEY, enabled ? "on" : "off");
    } catch (error) {
      // no-op
    }
  }

  function setHighContrast(enabled) {
    document.documentElement.dataset.highContrast = enabled ? "true" : "false";
    contrastToggle.setAttribute("aria-pressed", String(enabled));
    contrastToggle.textContent = enabled ? "High contrast: On" : "High contrast: Off";
    writeHighContrastPreference(enabled);
  }

  function buildCells() {
    const fragment = document.createDocumentFragment();
    for (let i = 0; i < engine.BOARD_CELLS; i += 1) {
      const cell = document.createElement("div");
      const row = Math.floor(i / BOARD_SIZE) + 1;
      const col = (i % BOARD_SIZE) + 1;
      cell.className = "board-cell";
      cell.setAttribute("role", "gridcell");
      cell.setAttribute("aria-label", `Row ${row}, Column ${col}, empty`);
      boardCellsByIndex.push(cell);
      fragment.appendChild(cell);
    }
    boardCells.appendChild(fragment);
  }

  function updateCellLabels(nextState) {
    nextState.board.forEach((value, index) => {
      const row = Math.floor(index / BOARD_SIZE) + 1;
      const col = (index % BOARD_SIZE) + 1;
      const cell = boardCellsByIndex[index];
      if (!cell) {
        return;
      }
      if (value === 0) {
        cell.setAttribute("aria-label", `Row ${row}, Column ${col}, empty`);
      } else {
        cell.setAttribute("aria-label", `Row ${row}, Column ${col}, tile ${value}`);
      }
    });
  }

  function getDirectionLabel(direction) {
    return {
      up: "up",
      down: "down",
      left: "left",
      right: "right",
    }[direction] || direction;
  }

  function updateGameStatus(nextState) {
    const lastMove = nextState.lastMove;
    let message = defaultStatusMessage;

    if (isPaused) {
      message = "Game paused. Press Resume to continue.";
    } else if (nextState.over) {
      message = `Game over. Final score ${nextState.score}. Press Restart to play again.`;
    } else if (nextState.won) {
      message = "You reached 2048. Keep playing to continue.";
    } else if (lastMove && !lastMove.moved) {
      message = `No tile movement for ${getDirectionLabel(lastMove.direction)}. Try another direction.`;
    } else if (lastMove && lastMove.moved) {
      message = `Moved ${getDirectionLabel(lastMove.direction)}.`;
    }

    statusText.textContent = message;
    ariaStatus.textContent = message;
  }

  function createTile(index, value, isNewTile, isMergedTile) {
    const tile = document.createElement("div");
    const row = Math.floor(index / BOARD_SIZE);
    const col = index % BOARD_SIZE;

    tile.className = "tile";
    tile.setAttribute("role", "img");
    tile.setAttribute("aria-label", `Tile ${value} at row ${row + 1}, column ${col + 1}`);
    tile.setAttribute("data-value", String(value));
    tile.style.setProperty("--row", row);
    tile.style.setProperty("--col", col);
    tile.style.setProperty("--text-color", textColorByValue[value] || "var(--tile-text-light)");

    if (isNewTile) {
      tile.classList.add("is-new");
    }
    if (isMergedTile) {
      tile.classList.add("is-merged");
    }

    const visibleValue = document.createElement("span");
    const srLabel = document.createElement("span");
    visibleValue.textContent = String(value);
    srLabel.className = "sr-only";
    srLabel.textContent = `Tile ${value}`;
    tile.appendChild(visibleValue);
    tile.appendChild(srLabel);
    return tile;
  }

  function getVisualStateMetadata(nextState) {
    const merged = new Set();
    const newTileIndex = nextState.lastMove && nextState.lastMove.spawned
      ? nextState.lastMove.spawned.index
      : -1;
    if (nextState.lastMove && Array.isArray(nextState.lastMove.movedTiles)) {
      for (let i = 0; i < nextState.lastMove.movedTiles.length; i += 1) {
        const info = nextState.lastMove.movedTiles[i];
        if (info && info.merged && Number.isInteger(info.to)) {
          merged.add(info.to);
        }
      }
    }
    return {
      merged,
      newTileIndex,
    };
  }

  function render(nextState) {
    const { merged, newTileIndex } = getVisualStateMetadata(nextState);

    state = nextState;
    if (state.score > bestScore) {
      bestScore = state.score;
    }
    boardTiles.innerHTML = "";

    nextState.board.forEach((value, index) => {
      if (value > 0) {
        const tile = createTile(index, value, newTileIndex === index, merged.has(index));
        boardTiles.appendChild(tile);
      }
    });

    if (isPaused) {
      gameBoard.classList.add("is-paused");
    } else {
      gameBoard.classList.remove("is-paused");
    }

    scoreValue.textContent = String(nextState.score);
    moveValue.textContent = String(nextState.moveCount);
    highScoreValue.textContent = String(bestScore);
    timerValue.textContent = formatElapsed(elapsedMs);
    if (isPaused) {
      gameBoard.setAttribute(
        "aria-label",
        `2048 board, score ${nextState.score}, move ${nextState.moveCount}, paused`,
      );
    } else {
      gameBoard.setAttribute("aria-label", `2048 board, score ${nextState.score}, move ${nextState.moveCount}`);
    }
    updateCellLabels(nextState);
    updateGameStatus(nextState);
    persistSession();
    if (!isPaused && !state.over) {
      startTimer();
    }
    undoButton.disabled = isPaused || state.history.length === 0;
    pauseButton.disabled = state.over;
    pauseButton.textContent = isPaused ? "Resume" : "Pause";
    pauseButton.setAttribute("aria-pressed", String(isPaused));
    directionButtons.forEach((button) => {
      button.disabled = state.over || isPaused;
    });
    gameBoard.focus({ preventScroll: true });
  }

  function startNewGame() {
    stopTimer();
    const seed = (typeof crypto !== "undefined" && crypto.getRandomValues)
      ? crypto.getRandomValues(new Uint32Array(1))[0]
      : Date.now();
    state = createInitialState(seed);
    isPaused = false;
    elapsedMs = 0;
    render(state);
    setStatus("New game started.");
    gameBoard.focus({ preventScroll: true });
  }

  function handleMove(direction) {
    if (inputLock.active || isPaused) {
      return;
    }
    if (state.over) {
      setStatus("Game over. Press Restart to continue.");
      gameBoard.focus({ preventScroll: true });
      return;
    }

    const result = executeMove(state, direction);
    render(result.state);
    const moved = result.state.lastMove && result.state.lastMove.moved;
    beginInputLock(moved ? transitionLockMs : inputProfile.noMoveLockMs);
    if (result.state.over) {
      resetControlState();
      stopTimer();
      persistSession();
      return;
    }
  }

  function handleUndo() {
    if (isPaused) {
      setStatus("Resume to undo.");
      return;
    }
    const result = undo(state);
    if (!result.undone) {
      statusText.textContent = "No moves to undo.";
      ariaStatus.textContent = "No moves to undo.";
      return;
    }
    render(result.state);
  }

  function handlePauseToggle() {
    if (state.over) {
      setStatus("Game over. Press Restart to continue.");
      return;
    }

    if (isPaused) {
      isPaused = false;
      persistSession();
      startTimer();
      setStatus("Game resumed.");
      resetControlState();
      render(state);
      return;
    }

    isPaused = true;
    stopTimer();
    persistSession();
    setStatus("Game paused.");
    render(state);
  }

  function handleSwipeStart(event) {
    if (!inputProfile.swipe.enabled || !isPointerAllowed(event.pointerType) || state.over || isPaused) {
      return;
    }
    if (event.pointerType === "mouse" && event.button !== 0) {
      return;
    }
    clearSwipeState();
    swipeState.active = true;
    swipeState.pointerId = event.pointerId;
    swipeState.startX = event.clientX;
    swipeState.startY = event.clientY;
    if (typeof event.target.setPointerCapture === "function") {
      try {
        event.target.setPointerCapture(event.pointerId);
      } catch (error) {
        // no-op
      }
    }
    event.preventDefault();
  }

  function handleSwipeMove(event) {
    if (!swipeState.active || event.pointerId !== swipeState.pointerId || swipeState.handled) {
      return;
    }

    const deltaX = event.clientX - swipeState.startX;
    const deltaY = event.clientY - swipeState.startY;
    const direction = getSwipeDirection(deltaX, deltaY);
    if (!direction) {
      return;
    }

    swipeState.handled = true;
    swipeState.direction = direction;
    handleMove(direction);
    event.preventDefault();
  }

  function handleSwipeEnd(event) {
    if (!swipeState.active || event.pointerId !== swipeState.pointerId) {
      return;
    }

    if (!swipeState.handled) {
      const deltaX = event.clientX - swipeState.startX;
      const deltaY = event.clientY - swipeState.startY;
      const direction = getSwipeDirection(deltaX, deltaY);
      if (direction) {
        swipeState.handled = true;
        swipeState.direction = direction;
        handleMove(direction);
      }
    }

    clearSwipeState();
  }

  function handleBoardKeydown(event) {
    const direction = mapDirectionFromKey(event.key);
    if (!direction) {
      return;
    }
    const token = `${event.code}:${event.key}`;
    if (pressedKeys.has(token) || pressedKeys.has(event.key)) {
      return;
    }
    pressedKeys.add(token);
    pressedKeys.add(event.key);
    event.preventDefault();
    handleMove(direction);
  }

  function handleBoardKeyup(event) {
    pressedKeys.delete(`${event.code}:${event.key}`);
    pressedKeys.delete(event.key);
  }

  function bindInputs() {
    gameBoard.addEventListener("keydown", handleBoardKeydown);
    gameBoard.addEventListener("keyup", handleBoardKeyup);
    gameBoard.addEventListener("click", () => {
      gameBoard.focus({ preventScroll: true });
    });

    if (inputProfile.swipe.enabled) {
      gameBoard.addEventListener("pointerdown", handleSwipeStart);
      gameBoard.addEventListener("pointermove", handleSwipeMove);
      gameBoard.addEventListener("pointerup", handleSwipeEnd);
      gameBoard.addEventListener("pointercancel", clearSwipeState);
      gameBoard.addEventListener("pointerleave", clearSwipeState);
    }

    if (inputProfile.buttons.enabled) {
      directionButtons.forEach((button) => {
        button.addEventListener("click", () => handleMove(button.dataset.dir));
      });
    }

    newGameButton.addEventListener("click", () => {
      resetControlState();
      startNewGame();
    });

    undoButton.addEventListener("click", handleUndo);
    pauseButton.addEventListener("click", handlePauseToggle);

    contrastToggle.addEventListener("click", () => {
      const enabled = document.documentElement.dataset.highContrast !== "true";
      setHighContrast(enabled);
    });

    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        persistSession();
        return;
      }
      if (!document.hidden) {
        gameBoard.focus({ preventScroll: true });
      }
    });

    window.addEventListener("beforeunload", () => {
      persistSession();
      stopTimer();
    });
  }

  function hydrateFromStorage() {
    const persisted = loadPersistedSession();
    if (!persisted) {
      return;
    }

    state = persisted.state;
    bestScore = clampNonNegativeInteger(persisted.bestScore, state.score);
    if (state.score > bestScore) {
      bestScore = state.score;
    }

    elapsedMs = clampNonNegativeInteger(persisted.elapsedMs, 0);
    isPaused = Boolean(persisted.isPaused);

    if (!isPaused && !state.over) {
      const lastSavedAt = clampNonNegativeInteger(persisted.lastSavedAt, 0);
      const now = Date.now();
      if (lastSavedAt && now > lastSavedAt) {
        elapsedMs += now - lastSavedAt;
      }
    }
  }

  function boot() {
    gameBoard.setAttribute("tabindex", "0");
    gameBoard.setAttribute("role", "grid");
    hydrateFromStorage();
    buildCells();
    setHighContrast(readHighContrastPreference());
    bindInputs();
    render(state);
    if (isPaused || state.over) {
      stopTimer();
    } else {
      startTimer();
    }
    gameBoard.focus({ preventScroll: true });
  }

  boot();
})();
