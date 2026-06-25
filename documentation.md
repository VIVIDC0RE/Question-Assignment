# QuestionAssignment

**Module:** `QuestionAssignment`  
**Author:** VIVIDC0RE  
**Copyright:** Ranking Manager © 2026

Server-side quiz and application manager. Handles question assignment, response validation, and grading with full anti-exploit coverage — all correctness logic lives server-side; the client only ever sees stripped question data.

---

## Overview

```
QuestionAssignment
├── Configuration   (totalQuestions, maximumStrikes)
└── Entries         (question pool)
```

Player state is stored in a private `PlayerData` table keyed by `UserId`. Clients receive a sanitized copy of questions (no `correctIndex`, no response metadata).

---

## Configuration

Loaded from `script.Configuration`. Expected fields:

| Field | Type | Description |
|---|---|---|
| `totalQuestions` | `number` | How many questions to draw per application |
| `maximumStrikes` | `number` | Strike count that triggers `OnStrikeThresholdMet` |

---

## Signals

### `QuestionAssignment.OnSpoofed`
Fired when a player triggers a validation failure.

```lua
QuestionAssignment.OnSpoofed:Connect(function(player: Player, reason: string)
    -- log or kick
end)
```

### `QuestionAssignment.OnStrikeThresholdMet`
Fired when a player's strike count reaches `MaxStrikes`.

```lua
QuestionAssignment.OnStrikeThresholdMet:Connect(function(player: Player)
    -- end application
end)
```

---

## Properties

| Property | Type | Description |
|---|---|---|
| `TotalQuestions` | `number` | Mirror of `Configuration.totalQuestions` |
| `MaxStrikes` | `number` | Mirror of `Configuration.maximumStrikes` |
| `AllEntries` | `table` | Full question pool from `script.Entries` |

---

## API

### `AssignQuestionsToPlayer(player, clientSafe?)`

Draws a randomized subset of questions from the pool and registers the player's session. Shuffles answer options per-question; correct index is re-resolved after shuffle.

Errors if the player already has an active session.

```lua
-- Server: store internally, return nothing
QuestionAssignment.AssignQuestionsToPlayer(player)

-- Server: assign and immediately return sanitized copy (for RemoteFunction reply)
local safeQuestions = QuestionAssignment.AssignQuestionsToPlayer(player, true)
```

**Parameters**

| Name | Type | Description |
|---|---|---|
| `player` | `Player` | Target player |
| `clientSafe` | `boolean?` | If `true`, returns the sanitized question list (see `GetPlayerQuestions`) |

**Returns** `table?` — sanitized question list if `clientSafe`, otherwise the raw internal list. Returns nothing if `clientSafe` is falsy.

**Errors** if the player already has an ongoing application, or if no questions are available.

---

### `GetPlayerQuestions(player, clientSafe?)`

Returns the player's assigned questions. Pass `clientSafe = true` when sending to the client — this strips `correctIndex` and all response metadata.

```lua
local questions = QuestionAssignment.GetPlayerQuestions(player, true)
-- questions[i] = { questionText: string, answerOptions: { { responseText: string } } }
```

**Returns** `table | false` — question list, or `false` if the player has no session.

---

### `AddResponse(player, questionIndex, selectedAnswer)`

Records a player's answer for a question. Enforces sequential order (out-of-order answers spoof), prevents overwriting previous answers, and validates that the submitted text matches a real answer option.

```lua
local result = QuestionAssignment.AddResponse(player, 1, "Paris")
-- result: "success" | "spoofed"
```

**Parameters**

| Name | Type | Description |
|---|---|---|
| `player` | `Player` | Answering player |
| `questionIndex` | `number` | Must equal the player's current question index |
| `selectedAnswer` | `string` | Must be the `responseText` of one of the question's options |

**Returns** `"success"` or `"spoofed"`.

**Spoof triggers:**
- Player has no session
- `questionIndex` is out of order
- `selectedAnswer` is not a valid option for the question
- Attempting to overwrite a previously recorded answer

---

### `IsCorrectAnswer(player, questionIndex, selectedAnswer)`

Checks correctness without recording a response. Useful for live feedback or pre-submission checks.

```lua
local correct = QuestionAssignment.IsCorrectAnswer(player, 2, "Berlin")
```

**Returns** `boolean` — `false` if the player has no session or the question doesn't exist.

---

### `AddStrike(player)`

Increments the player's strike counter. Fires `OnStrikeThresholdMet` if `strikes >= MaxStrikes`.

```lua
QuestionAssignment.AddStrike(player)
```

---

### `GradeApplication(player)`

Grades the completed application using pre-calculated correctness values stored during `AddResponse`. All questions must have responses before calling — premature calls return `"spoofed"`.

```lua
local correct, incorrect = QuestionAssignment.GradeApplication(player)
```

**Returns** `(number, number)` — correct and incorrect counts, or `"spoofed"` on failure.

**Spoof triggers:**
- Player has no session
- Not all questions have been answered

---

### `RemovePlayer(player)`

Clears all session data for the player. Call this on `Players.PlayerRemoving` and after an application completes.

```lua
QuestionAssignment.RemovePlayer(player)
```

---

## Question Entry Schema

Questions in `script.Entries` must conform to:

```lua
{
    questionText  = "What is the capital of France?",  -- string
    answerOptions = {
        { responseText = "Paris"   },
        { responseText = "Berlin"  },
        { responseText = "Madrid"  },
        { responseText = "Lisbon"  },
    },
    correctIndex = 1,  -- 1-based index into answerOptions
}
```

Answer options are shuffled per-assignment; `correctIndex` is re-resolved automatically.

---

## Typical Server Flow

```lua
local Players           = game:GetService("Players")
local QuestionAssignment = require(path.to.QuestionAssignment)

QuestionAssignment.OnSpoofed:Connect(function(player, reason)
    warn(player.Name, "spoofed:", reason)
    -- kick or flag
end)

QuestionAssignment.OnStrikeThresholdMet:Connect(function(player)
    QuestionAssignment.RemovePlayer(player)
    -- notify player application ended
end)

-- RemoteFunction: start application
StartApplicationRemote.OnServerInvoke = function(player)
    return QuestionAssignment.AssignQuestionsToPlayer(player, true)
end

-- RemoteFunction: submit answer
SubmitAnswerRemote.OnServerInvoke = function(player, questionIndex, selectedAnswer)
    return QuestionAssignment.AddResponse(player, questionIndex, selectedAnswer)
end

-- RemoteFunction: finish and grade
FinishRemote.OnServerInvoke = function(player)
    local correct, incorrect = QuestionAssignment.GradeApplication(player)
    QuestionAssignment.RemovePlayer(player)
    return correct, incorrect
end

Players.PlayerRemoving:Connect(function(player)
    QuestionAssignment.RemovePlayer(player)
end)
```
