(() => {
  const PREF_KEY = "sf2048_high_contrast";
  const engine = window.Game2048;
  if (!engine) {
    return;
  }

  const {
    BOARD_SIZE,
    createInitialState,
    executeMove,
    undo,
  } = engine;

  const gameBoard = document.getElementById("gameBoard");
  const boardCells = document.getElementById("boardCells");
  const boardTiles = document.getElementById("boardTiles");
  const statusText = document.getElementById("statusText");
  const ariaStatus = document.getElementById("ariaStatus");
  const scoreValue = document.getElementById("scoreValue");
  const moveValue = document.getElementById("moveValue");
  const newGameButton = document.getElementById("newGameButton");
  const undoButton = document.getElementById("undoButton");
  const contrastToggle = document.getElementById("contrastToggle");
  const directionButtons = document.querySelectorAll("[data-dir]");

  const stateSeed = (typeof crypto !== "undefined" && crypto.getRandomValues)
    ? crypto.getRandomValues(new Uint32Array(1))[0]
    : Date.now();

  const boardCellsByIndex = [];
  const keyToDirection = {
    ArrowUp: "up",
    ArrowDown: "down",
    ArrowLeft: "left",
    ArrowRight: "right",
    k: "up",
    j: "down",
    h: "left",
    l: "right",
    w: "up",
    s: "down",
    a: "left",
    d: "right",
  };

  const textColorByValue = {
    2: "var(--tile-text-dark)",
    4: "var(--tile-text-dark)",
  };

  let state = createInitialState(stateSeed);

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
    let message = "Use directional controls to move tiles.";

    if (nextState.over) {
      message = "Game over. Press New Game to play again.";
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
    boardTiles.innerHTML = "";

    nextState.board.forEach((value, index) => {
      if (value > 0) {
        const tile = createTile(index, value, newTileIndex === index, merged.has(index));
        boardTiles.appendChild(tile);
      }
    });

    scoreValue.textContent = String(nextState.score);
    moveValue.textContent = String(nextState.moveCount);
    gameBoard.setAttribute("aria-label", `2048 board, score ${nextState.score}, move ${nextState.moveCount}`);
    updateCellLabels(nextState);
    updateGameStatus(nextState);
    gameBoard.focus({ preventScroll: true });
  }

  function startNewGame() {
    const seed = (typeof crypto !== "undefined" && crypto.getRandomValues)
      ? crypto.getRandomValues(new Uint32Array(1))[0]
      : Date.now();
    state = createInitialState(seed);
    render(state);
    statusText.textContent = "New game started.";
    ariaStatus.textContent = "New game started.";
  }

  function handleMove(direction) {
    if (state.over) {
      statusText.textContent = "Game over. Press New Game to continue.";
      ariaStatus.textContent = "Game over. Press New Game to continue.";
      gameBoard.focus({ preventScroll: true });
      return;
    }
    const result = executeMove(state, direction);
    render(result.state);
  }

  function handleUndo() {
    const result = undo(state);
    if (!result.undone) {
      statusText.textContent = "No moves to undo.";
      ariaStatus.textContent = "No moves to undo.";
      return;
    }
    render(result.state);
  }

  function handleBoardKeydown(event) {
    const direction = keyToDirection[event.key];
    if (!direction) {
      return;
    }
    event.preventDefault();
    handleMove(direction);
  }

  function bindInputs() {
    gameBoard.addEventListener("keydown", handleBoardKeydown);
    gameBoard.addEventListener("click", () => {
      gameBoard.focus({ preventScroll: true });
    });

    directionButtons.forEach((button) => {
      button.addEventListener("click", () => handleMove(button.dataset.dir));
    });

    newGameButton.addEventListener("click", startNewGame);
    undoButton.addEventListener("click", handleUndo);

    contrastToggle.addEventListener("click", () => {
      const enabled = document.documentElement.dataset.highContrast !== "true";
      setHighContrast(enabled);
    });

    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) {
        gameBoard.focus({ preventScroll: true });
      }
    });
  }

  function boot() {
    gameBoard.setAttribute("tabindex", "0");
    gameBoard.setAttribute("role", "grid");
    buildCells();
    setHighContrast(readHighContrastPreference());
    bindInputs();
    render(state);
    gameBoard.focus({ preventScroll: true });
  }

  boot();
})();
