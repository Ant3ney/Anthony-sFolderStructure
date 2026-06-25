const assert = require("node:assert");
const {
  canMove,
  createInitialState,
  createSeededRng,
  deserializeGameState,
  executeMove,
  isGameOver,
  listLegalMoves,
  normalizeState,
  serializeGameState,
  undo,
} = require("./engine");

{
  const state = createInitialState(1337);
  const moves = listLegalMoves(state);
  assert.ok(Array.isArray(moves));
  assert.ok(moves.every((direction) => ["left", "right", "up", "down"].includes(direction)));
}

{
  const state = {
    board: [2, 2, 0, 0, 4, 2, 0, 0, 0, 0, 8, 0, 0, 0, 0, 16],
    rngState: 123,
    moveCount: 0,
    score: 0,
    history: [],
  };
  const result = executeMove(state, "left");
  assert.deepStrictEqual(result.state.board, [4, 0, 0, 0, 4, 2, 0, 0, 0, 8, 0, 0, 0, 0, 0, 16]);
  assert.strictEqual(result.scoreDelta, 4);
  assert.strictEqual(result.metadata.direction, "left");
  assert.strictEqual(result.metadata.moved, true);
}

{
  const blocked = {
    board: [
      2, 4, 2, 4,
      4, 2, 4, 2,
      2, 4, 2, 4,
      4, 2, 4, 2,
    ],
    rngState: 55,
  };
  assert.strictEqual(canMove(blocked, "left"), false);
  assert.strictEqual(canMove(blocked, "right"), false);
  assert.strictEqual(canMove(blocked, "up"), false);
  assert.strictEqual(canMove(blocked, "down"), false);
  assert.strictEqual(listLegalMoves(blocked).length, 0);
  assert.strictEqual(isGameOver(blocked), true);
}

{
  const seed = "deterministic-seed";
  const start = {
    board: [2, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0],
    rngState: createSeededRng(seed).getState(),
    score: 0,
    moveCount: 0,
    history: [],
  };
  const leftA = executeMove(start, "left");
  const leftB = executeMove(start, "left", {
    rng: createSeededRng(seed),
  });
  assert.deepStrictEqual(leftA.state.board, leftB.state.board);
  assert.strictEqual(leftA.state.rngState, leftB.state.rngState);
}

{
  const roundTrip = {
    board: [0, 2, 2, 0, 0, 4, 4, 0, 2, 0, 0, 2, 0, 0, 0, 8],
    rngState: 2026,
    score: 14,
    moveCount: 2,
  };
  const before = executeMove(roundTrip, "right");
  const serialized = serializeGameState(before.state);
  const after = deserializeGameState(serialized);
  assert.strictEqual(serialized.includes("version"), true);
  assert.deepStrictEqual(after.board, before.state.board);
  assert.strictEqual(after.score, before.state.score);
  assert.strictEqual(after.moveCount, before.state.moveCount);
}

{
  const undos = executeMove(
    {
      board: [2, 2, 0, 0, 4, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 16],
      rngState: 17,
      score: 0,
      moveCount: 0,
      history: [],
    },
    "left",
  );
  const undone = undo(undos.state);
  assert.strictEqual(undone.undone, true);
  assert.deepStrictEqual(
    undone.state.board,
    [2, 2, 0, 0, 4, 0, 0, 0, 0, 8, 0, 0, 0, 0, 0, 16],
  );
  assert.strictEqual(undone.state.score, 0);
  assert.strictEqual(undone.state.moveCount, 0);
  assert.strictEqual(undone.state.rngState, 17);
}

{
  const blocked = normalizeState({
    board: [
      2, 4, 2, 4,
      4, 2, 4, 2,
      2, 4, 2, 4,
      4, 2, 4, 2,
    ],
    rngState: 321,
    score: 999,
    moveCount: 12,
    over: false,
  });
  const result = executeMove(blocked, "left");
  assert.strictEqual(result.state.over, true);
  assert.strictEqual(result.metadata.over, true);
  assert.strictEqual(result.metadata.moved, false);
}

{
  const start = {
    board: [2, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0, 8, 0, 0, 0],
    rngState: createSeededRng("seed").getState(),
    score: 0,
    moveCount: 0,
    history: [],
  };
  const seededA = executeMove(start, "left", { seed: "seed" });
  const seededB = executeMove(start, "left", { seed: "seed" });
  assert.deepStrictEqual(seededA.state.board, seededB.state.board);
  assert.strictEqual(seededA.state.rngState, seededB.state.rngState);
}

{
  const state = executeMove({
    board: [4, 0, 0, 4, 2, 2, 0, 0, 0, 0, 8, 0, 0, 0, 0, 16],
    rngState: 88,
    score: 0,
    moveCount: 0,
    history: [],
  }, "left");
  const serialized = serializeGameState(state.state);
  const raw = JSON.parse(serialized);
  delete raw.version;
  const restored = deserializeGameState(raw);
  assert.deepStrictEqual(restored.board, state.state.board);
}
