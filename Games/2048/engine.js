const BOARD_SIZE = 4;
const BOARD_CELLS = BOARD_SIZE * BOARD_SIZE;
const WIN_TILE = 2048;
const SPAWN_TWO_CHANCE = 0.9;
const DEFAULT_RANDOM_SEED = 0x6fbe;
const SERIALIZATION_VERSION = 1;
const DIRECTIONS = ["left", "right", "up", "down"];
const ALLOWED_DIRECTIONS = new Set(DIRECTIONS);

function validateDirection(direction) {
  if (!ALLOWED_DIRECTIONS.has(direction)) {
    throw new TypeError("direction must be one of: left, right, up, down");
  }
}

function validateBoard(board) {
  if (!Array.isArray(board)) {
    throw new TypeError("State board must be an array.");
  }
  if (board.length !== BOARD_CELLS) {
    throw new TypeError("State board must be a length-16 array.");
  }
}

function isPowerOfTwo(value) {
  return value === 0 || (value > 0 && (value & (value - 1)) === 0);
}

function normalizeSeed(seed) {
  if (typeof seed === "number" && Number.isFinite(seed)) {
    const normalized = seed >>> 0;
    return normalized === 0 ? DEFAULT_RANDOM_SEED : normalized;
  }

  if (typeof seed === "bigint") {
    const normalized = Number(seed & 0xffffffffn) >>> 0;
    return normalized === 0 ? DEFAULT_RANDOM_SEED : normalized;
  }

  if (typeof seed === "string" && seed.length > 0) {
    let h = 0x811c9dc5;
    for (let i = 0; i < seed.length; i += 1) {
      h ^= seed.charCodeAt(i);
      h = Math.imul(h, 0x01000193);
    }
    const normalized = h >>> 0;
    return normalized === 0 ? DEFAULT_RANDOM_SEED : normalized;
  }

  return DEFAULT_RANDOM_SEED;
}

function createSeededRng(seed) {
  let state = normalizeSeed(seed);

  function nextUint32() {
    state ^= (state << 13) >>> 0;
    state ^= state >>> 17;
    state ^= (state << 5) >>> 0;
    return state >>> 0;
  }

  return {
    nextFloat() {
      return nextUint32() / 0x100000000;
    },
    nextInt(maxExclusive) {
      if (!Number.isInteger(maxExclusive) || maxExclusive <= 0) {
        throw new TypeError("maxExclusive must be a positive integer.");
      }
      return Math.floor(this.nextFloat() * maxExclusive);
    },
    getState() {
      return state >>> 0;
    },
    setState(nextState) {
      state = normalizeSeed(nextState);
    },
    clone() {
      return createSeededRng(state);
    },
  };
}

function isSeededRng(value) {
  return (
    value
    && typeof value === "object"
    && typeof value.nextFloat === "function"
    && typeof value.nextInt === "function"
    && typeof value.getState === "function"
  );
}

function cloneBoard(board) {
  const cloned = new Array(BOARD_CELLS);
  for (let i = 0; i < BOARD_CELLS; i += 1) {
    cloned[i] = board[i];
  }
  return cloned;
}

function freezeState(state) {
  return Object.freeze({
    version: state.version,
    board: Object.freeze(state.board),
    score: state.score,
    rngState: state.rngState,
    moveCount: state.moveCount,
    won: state.won,
    over: state.over,
    history: Object.freeze(state.history),
    lastMove: state.lastMove && Object.freeze(state.lastMove),
  });
}

function normalizeInt(value, fallback) {
  const n = Number(value);
  if (!Number.isFinite(n)) {
    return fallback;
  }
  const asInt = Math.trunc(n);
  return asInt < 0 ? fallback : asInt;
}

function normalizeTileValue(value) {
  if (value === 0 || value === null || value === undefined) {
    return 0;
  }

  const n = Number(value);
  if (!Number.isInteger(n) || n < 0 || !isPowerOfTwo(n)) {
    throw new TypeError("Tile values must be 0 or powers of two.");
  }

  return n;
}

function normalizeBoardValues(board) {
  validateBoard(board);
  const normalized = new Array(BOARD_CELLS);
  for (let i = 0; i < BOARD_CELLS; i += 1) {
    normalized[i] = normalizeTileValue(board[i]);
  }
  return Object.freeze(normalized);
}

function normalizeMoveMeta(lastMove) {
  if (!lastMove || typeof lastMove !== "object") {
    return null;
  }
  const spawned = lastMove.spawned;
  return Object.freeze({
    direction: typeof lastMove.direction === "string" && ALLOWED_DIRECTIONS.has(lastMove.direction)
      ? lastMove.direction
      : null,
    moved: Boolean(lastMove.moved),
    scoreDelta: normalizeInt(lastMove.scoreDelta, 0),
    mergedCount: normalizeInt(lastMove.mergedCount, 0),
    movedTiles: Array.isArray(lastMove.movedTiles) ? lastMove.movedTiles : null,
    spawned: spawned && typeof spawned === "object" && Number.isInteger(spawned.index) && Number.isInteger(spawned.value)
      ? Object.freeze({
          index: normalizeInt(spawned.index, 0),
          value: normalizeInt(spawned.value, 0),
        })
      : null,
  });
}

function normalizeHistory(history) {
  if (!Array.isArray(history)) {
    return [];
  }
  return history.map((entry) => normalizeHistoryEntry(entry));
}

function normalizeHistoryEntry(entry) {
  if (!entry || typeof entry !== "object") {
    throw new TypeError("history entry must be an object");
  }

  const board = normalizeBoardValues(Array.isArray(entry.board) ? entry.board : new Array(BOARD_CELLS).fill(0));
  return freezeState({
    version: SERIALIZATION_VERSION,
    board,
    score: normalizeInt(entry.score, 0),
    rngState: normalizeSeed(entry.rngState ?? DEFAULT_RANDOM_SEED),
    moveCount: normalizeInt(entry.moveCount, 0),
    won: hasTargetTile(board),
    over: !hasLegalMovesFromBoard(board),
    history: [],
    lastMove: normalizeMoveMeta(entry.lastMove),
  });
}

function normalizeState(rawState = {}) {
  const board = normalizeBoardValues(
    Array.isArray(rawState.board) ? rawState.board : new Array(BOARD_CELLS).fill(0),
  );
  const score = normalizeInt(rawState.score, 0);
  const rngState = normalizeSeed(rawState.rngState ?? DEFAULT_RANDOM_SEED);
  const moveCount = normalizeInt(rawState.moveCount, 0);
  const lastMove = normalizeMoveMeta(rawState.lastMove);
  const history = normalizeHistory(rawState.history);

  return freezeState({
    version: SERIALIZATION_VERSION,
    board,
    score,
    rngState,
    moveCount,
    won: hasTargetTile(board),
    over: !hasLegalMovesFromBoard(board),
    history,
    lastMove,
  });
}

function hasTargetTile(board) {
  for (let i = 0; i < BOARD_CELLS; i += 1) {
    if (board[i] >= WIN_TILE) {
      return true;
    }
  }
  return false;
}

function hasEmptyCells(board) {
  for (let i = 0; i < BOARD_CELLS; i += 1) {
    if (board[i] === 0) {
      return true;
    }
  }
  return false;
}

function arraysEqual(a, b) {
  if (a.length !== b.length) {
    return false;
  }
  for (let i = 0; i < a.length; i += 1) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

function getLineIndices(direction, line) {
  if (!Number.isInteger(line) || line < 0 || line >= BOARD_SIZE) {
    throw new TypeError("line must be 0..3");
  }

  if (direction === "left") {
    return [line * 4, line * 4 + 1, line * 4 + 2, line * 4 + 3];
  }
  if (direction === "right") {
    return [line * 4 + 3, line * 4 + 2, line * 4 + 1, line * 4];
  }
  if (direction === "up") {
    return [line, line + 4, line + 8, line + 12];
  }
  return [line + 12, line + 8, line + 4, line];
}

function mergeLine(cells, direction, lineIndices) {
  const movingTiles = [];
  for (let i = 0; i < cells.length; i += 1) {
    if (cells[i] !== 0) {
      movingTiles.push({
        value: cells[i],
        index: lineIndices[i],
      });
    }
  }

  const mergedLine = new Array(4).fill(0);
  const tileMetadata = [];
  let scoreGain = 0;

  let target = 0;
  for (let i = 0; i < movingTiles.length; i += 1) {
    const current = movingTiles[i];
    const next = movingTiles[i + 1];

    if (next && next.value === current.value) {
      const value = current.value * 2;
      mergedLine[target] = value;
      scoreGain += value;
      tileMetadata.push({
        direction,
        value,
        from: [current.index, next.index],
        to: lineIndices[target],
        merged: true,
      });
      target += 1;
      i += 1;
    } else {
      mergedLine[target] = current.value;
      tileMetadata.push({
        direction,
        value: current.value,
        from: [current.index],
        to: lineIndices[target],
        merged: false,
      });
      target += 1;
    }
  }

  const moved = !arraysEqual(mergedLine, cells);
  return { mergedLine, tileMetadata, scoreGain, moved };
}

function projectMove(board, direction) {
  validateDirection(direction);

  const nextBoard = cloneBoard(board);
  const movedTiles = [];
  let scoreDelta = 0;
  let hasShifted = false;

  for (let line = 0; line < BOARD_SIZE; line += 1) {
    const lineIndices = getLineIndices(direction, line);
    const lineValues = [
      board[lineIndices[0]],
      board[lineIndices[1]],
      board[lineIndices[2]],
      board[lineIndices[3]],
    ];
    const result = mergeLine(lineValues, direction, lineIndices);

    nextBoard[lineIndices[0]] = result.mergedLine[0];
    nextBoard[lineIndices[1]] = result.mergedLine[1];
    nextBoard[lineIndices[2]] = result.mergedLine[2];
    nextBoard[lineIndices[3]] = result.mergedLine[3];

    if (result.moved) {
      hasShifted = true;
    }
    if (result.scoreGain > 0) {
      scoreDelta += result.scoreGain;
    }
    for (let i = 0; i < result.tileMetadata.length; i += 1) {
      const tile = result.tileMetadata[i];
      const wasStationarySingleSource = tile.from.length === 1 && tile.from[0] === tile.to;
      if (!wasStationarySingleSource || tile.from.length > 1) {
        movedTiles.push(tile);
      }
    }
  }

  return {
    board: Object.freeze(nextBoard),
    moved: hasShifted,
    scoreDelta,
    mergedCount: movedTiles.length,
    movedTiles: Object.freeze(movedTiles),
  };
}

function randomEmptyTileIndex(board, rng) {
  const candidates = [];
  for (let i = 0; i < BOARD_CELLS; i += 1) {
    if (board[i] === 0) {
      candidates.push(i);
    }
  }

  if (!candidates.length) {
    return null;
  }

  return candidates[rng.nextInt(candidates.length)];
}

function spawnTile(board, rng) {
  const emptyIndex = randomEmptyTileIndex(board, rng);
  if (emptyIndex === null) {
    return {
      board: board.slice(),
      spawned: null,
      rngState: rng.getState(),
    };
  }

  const nextBoard = board.slice();
  nextBoard[emptyIndex] = rng.nextFloat() < SPAWN_TWO_CHANCE ? 2 : 4;
  return {
    board: Object.freeze(nextBoard),
    spawned: Object.freeze({
      index: emptyIndex,
      value: nextBoard[emptyIndex],
    }),
    rngState: rng.getState(),
  };
}

function makeHistoryRecord(state) {
  return freezeState({
    version: SERIALIZATION_VERSION,
    board: state.board,
    score: state.score,
    rngState: state.rngState,
    moveCount: state.moveCount,
    won: state.won,
    over: state.over,
    history: [],
    lastMove: state.lastMove,
  });
}

function hasLegalMovesFromBoard(board) {
  if (hasEmptyCells(board)) {
    return true;
  }
  for (const direction of DIRECTIONS) {
    if (projectMove(board, direction).moved) {
      return true;
    }
  }
  return false;
}

function canMove(state, direction) {
  const normalized = normalizeState(state);
  validateDirection(direction);
  return projectMove(normalized.board, direction).moved;
}

function listLegalMoves(state) {
  const normalized = normalizeState(state);
  const moves = [];
  for (const direction of DIRECTIONS) {
    if (projectMove(normalized.board, direction).moved) {
      moves.push(direction);
    }
  }
  return moves;
}

function buildMoveMetadata(direction, moved, projected, spawned) {
  return Object.freeze({
    direction,
    moved,
    scoreDelta: moved ? projected.scoreDelta : 0,
    mergedCount: moved ? projected.mergedCount : 0,
    movedTiles: moved ? projected.movedTiles : [],
    spawned,
    won: false,
    over: false,
  });
}

function executeMove(state, direction, options = {}) {
  const normalized = normalizeState(state);
  validateDirection(direction);
  const projected = projectMove(normalized.board, direction);

  if (!projected.moved) {
    const nextState = normalizeState({
      ...normalized,
      board: normalized.board,
      score: normalized.score,
      rngState: normalized.rngState,
      moveCount: normalized.moveCount,
      won: normalized.won,
      over: normalized.over,
      history: normalized.history,
      lastMove: normalized.lastMove,
    });
    const metadata = buildMoveMetadata(direction, false, projected, null);
    return {
      state: nextState,
      scoreDelta: 0,
      metadata: {
        ...metadata,
        won: nextState.won,
        over: nextState.over,
      },
    };
  }

  const rng = isSeededRng(options.rng)
    ? options.rng
    : createSeededRng(options.seed != null ? options.seed : normalized.rngState);

  const spawn = spawnTile(projected.board, rng);
  const nextState = freezeState({
    version: SERIALIZATION_VERSION,
    board: spawn.board,
    score: normalized.score + projected.scoreDelta,
    rngState: spawn.rngState,
    moveCount: normalized.moveCount + 1,
    won: hasTargetTile(spawn.board),
    over: !hasLegalMovesFromBoard(spawn.board),
    history: Object.freeze([...normalized.history, makeHistoryRecord(normalized)]),
    lastMove: Object.freeze({
      direction,
      moved: true,
      scoreDelta: projected.scoreDelta,
      mergedCount: projected.mergedCount,
      movedTiles: projected.movedTiles,
      spawned: spawn.spawned,
    }),
  });

  return {
    state: nextState,
    scoreDelta: projected.scoreDelta,
    metadata: {
      direction,
      moved: true,
      scoreDelta: projected.scoreDelta,
      mergedCount: projected.mergedCount,
      movedTiles: projected.movedTiles,
      spawned: spawn.spawned,
      won: nextState.won,
      over: nextState.over,
    },
  };
}

function isGameOver(boardOrState) {
  const state = normalizeState(
    boardOrState && boardOrState.board ? boardOrState : { board: boardOrState },
  );
  return state.over;
}

function undo(state) {
  const normalized = normalizeState(state);
  if (!normalized.history.length) {
    return {
      state: normalized,
      undone: false,
      metadata: { undone: false, reason: "no_history" },
    };
  }

  const restored = normalized.history[normalized.history.length - 1];
  const remainingHistory = normalized.history.slice(0, -1);
  return {
    state: freezeState({
      version: restored.version,
      board: restored.board,
      score: restored.score,
      rngState: restored.rngState,
      moveCount: restored.moveCount,
      won: restored.won,
      over: restored.over,
      history: Object.freeze(remainingHistory),
      lastMove: restored.lastMove,
    }),
    undone: true,
    metadata: { undone: true, direction: "undo", moved: false },
  };
}

function createInitialState(seed) {
  const rng = createSeededRng(seed);
  const emptyBoard = new Array(BOARD_CELLS).fill(0);
  const first = spawnTile(emptyBoard, rng);
  const second = spawnTile(first.board, rng);

  return freezeState({
    version: SERIALIZATION_VERSION,
    board: second.board,
    score: 0,
    rngState: second.rngState,
    moveCount: 0,
    won: hasTargetTile(second.board),
    over: !hasLegalMovesFromBoard(second.board),
    history: Object.freeze([]),
    lastMove: null,
  });
}

function serializeGameState(state) {
  const normalized = normalizeState(state);
  return JSON.stringify({
    version: SERIALIZATION_VERSION,
    board: normalized.board.slice(),
    score: normalized.score,
    rngState: normalized.rngState,
    moveCount: normalized.moveCount,
    won: normalized.won,
    over: normalized.over,
    history: normalized.history.map((entry) => ({
      version: entry.version,
      board: entry.board.slice(),
      score: entry.score,
      rngState: entry.rngState,
      moveCount: entry.moveCount,
      won: entry.won,
      over: entry.over,
      lastMove: entry.lastMove,
    })),
    lastMove: normalized.lastMove,
  });
}

function deserializeGameState(serialized) {
  let parsed = serialized;
  if (typeof serialized === "string") {
    try {
      parsed = JSON.parse(serialized);
    } catch (error) {
      throw new Error("deserializeGameState expects a valid JSON string.");
    }
  }

  if (!parsed || typeof parsed !== "object") {
    throw new TypeError("deserializeGameState expects a plain object or JSON string.");
  }

  if (parsed.version !== undefined && parsed.version !== SERIALIZATION_VERSION) {
    throw new Error(`Unsupported serialization version: ${parsed.version}`);
  }

  return normalizeState({
    ...parsed,
    version: SERIALIZATION_VERSION,
  });
}

module.exports = {
  BOARD_SIZE,
  BOARD_CELLS,
  WIN_TILE,
  createSeededRng,
  createInitialState,
  canMove,
  isMoveLegal: canMove,
  hasLegalMoves: hasLegalMovesFromBoard,
  move: executeMove,
  executeMove,
  listLegalMoves,
  legalMoves: listLegalMoves,
  isGameOver,
  isBlocked: isGameOver,
  undo,
  normalizeState,
  serialize: serializeGameState,
  serializeGameState,
  deserialize: deserializeGameState,
  deserializeGameState,
};
