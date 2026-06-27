--[=[
    @module RankingManager.QuestionAssignment
    @author VIVIDC0RE
    @copyright Ranking Manager © 2026

    A secure, server-based module for creating and managing unexploitable quizzes and applications.
    This system handles question assignment, validates player responses, and evaluates final application scores.

    Features:
    - Dynamic question selection from a predefined pool.
    - Server-side tracking of player progress to prevent client-side manipulation.
    - Evaluation logic for grading applications based on correctness and strike thresholds.
]=]

local QuestionAssignment = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Packages.Signal)
local TableUtil = require(ReplicatedStorage.Packages.TableUtil)
local Configuration = require(script.Configuration)

QuestionAssignment.TotalQuestions = Configuration.totalQuestions
QuestionAssignment.MaxStrikes = Configuration.maximumStrikes
QuestionAssignment.AllEntries = require(script.Entries)

local PlayerData = {}

QuestionAssignment.OnSpoofed = Signal.new() -- optional signal for when a player exploits
QuestionAssignment.OnStrikeThresholdMet = Signal.new() -- optional signal for strike threshold

--[=[
    Validates that the input is a Player instance.

    @param player (Player) The player to validate.
    @throws Error if the input is not a valid Player.
]=]
local function ValidatePlayer(player)
	assert(player and player:IsA("Player"), "Invalid Player.")
end

--[=[
    Retrieves internal player data.

    @param player (Player) The player whose data is being accessed.
    @return (table?) The internal data table for the player, or nil if not found.
]=]
local function GetPlayerInfo(player)
	return PlayerData[player.UserId]
end

--[=[
    Fires spoof signal and returns spoofed status.

    @param player (Player) The player being flagged.
    @param reason (string) The reason for spoofing.
    @return (string) Always returns "spoofed".
]=]
local function Spoof(player, reason)
	QuestionAssignment.OnSpoofed:Fire(player, reason)
	return "spoofed"
end

--[=[
    Retrieves and validates player info, firing spoof signal if invalid.

    @param player (Player) The player whose data is being accessed.
    @param spoofReason (string) The reason to provide if spoofing occurs.
    @return (table?, string?) The player info table, or nil and spoof result.
]=]
local function GetValidatedPlayerInfo(player, spoofReason)
	local info = GetPlayerInfo(player)
	if not info then
		return nil, Spoof(player, spoofReason or "playerData does not exist.")
	end
	return info
end

--[=[
    Clones a question entry and shuffles its answer options while maintaining correct index.
    Optimized to track correct answer position during shuffle.

    @param original (table) The original question entry.
    @return (table) A cloned and shuffled version of the question with updated correctIndex.
]=]
local function CloneQuestion(original)
	local clonedOptions = table.clone(original.answerOptions)
	local correctAnswer = original.answerOptions[original.correctIndex]
	local correctAnswerText = correctAnswer.responseText

	local shuffledOptions = TableUtil.Shuffle(clonedOptions)
	local newCorrectIndex

	for i, option in ipairs(shuffledOptions) do
		if option.responseText == correctAnswerText then
			newCorrectIndex = i
			break
		end
	end

	return {
		questionText = original.questionText,
		answerOptions = shuffledOptions,
		correctIndex = newCorrectIndex,
	}
end

--[=[
    Checks if a selected answer is valid for a given question.

    @param question (table) The question object.
    @param selectedAnswer (string) The answer text to validate.
    @return (boolean) True if the answer exists in the options, false otherwise.
]=]
local function IsValidAnswer(question, selectedAnswer)
	for _, option in ipairs(question.answerOptions) do
		if option.responseText == selectedAnswer then
			return true
		end
	end
	return false
end

--[=[
    Checks if a selected answer is correct for a given question.

    @param question (table) The question object.
    @param selectedAnswer (string) The answer text to validate.
    @return (boolean) True if the answer is correct, false otherwise.
]=]
local function IsCorrectAnswerForQuestion(question, selectedAnswer)
	local correctOption = question.answerOptions[question.correctIndex]
	return correctOption.responseText == selectedAnswer
end

--[=[
    Assigns a randomized set of questions to a player.

    @param player (Player) The player to assign questions to.
    @param clientSafe (boolean) If true, strips correctIndex and response metadata.
    @throws Error if no questions are selected or player already has an ongoing application.
]=]
function QuestionAssignment.AssignQuestionsToPlayer(player, clientSafe)
	ValidatePlayer(player)

	local existing = PlayerData[player.UserId]
	if existing then
		error("[AssignQuestionsToPlayer] Player already has an ongoing application.")
	end

	local questionsToSelect = math.min(QuestionAssignment.TotalQuestions, #QuestionAssignment.AllEntries)
	assert(questionsToSelect >= 1, "[AssignQuestionsToPlayer] No questions available")

	local shuffledPool = TableUtil.Shuffle(table.clone(QuestionAssignment.AllEntries))
	local selectedQuestions = {}

	for i = 1, questionsToSelect do
		local original = shuffledPool[i]
		assert(
			typeof(original) == "table"
				and typeof(original.questionText) == "string"
				and typeof(original.answerOptions) == "table",
			"[QuestionAssignment] Invalid question entry"
		)
		selectedQuestions[i] = CloneQuestion(original)
	end

	PlayerData[player.UserId] = {
		questions = selectedQuestions,
		responses = {},
		strikes = 0,
		currentQuestionIndex = 1,
		correctCount = 0,
	}

	if clientSafe then
		return QuestionAssignment.GetPlayerQuestions(player, true)
	end

	return selectedQuestions
end

--[=[
    Returns a player's assigned questions.
    Optionally strips sensitive data for client safety.

    @param player (Player) The player whose questions are being retrieved.
    @param clientSafe (boolean) If true, strips correctIndex and response metadata.
    @return (table) The list of questions.
]=]
function QuestionAssignment.GetPlayerQuestions(player, clientSafe)
	ValidatePlayer(player)

	local info = GetPlayerInfo(player)
	if not info then
		return false
	end

	if not clientSafe then
		return info.questions
	end

	local clientCopy = {}
	for i, question in ipairs(info.questions) do
		local safeQuestion = {
			questionText = question.questionText,
			answerOptions = {},
		}
		for j, option in ipairs(question.answerOptions) do
			safeQuestion.answerOptions[j] = { responseText = option.responseText }
		end
		clientCopy[i] = safeQuestion
	end

	return clientCopy
end

--[=[
    Checks if a player's selected answer is correct.

    @param player (Player) The player being evaluated.
    @param questionIndex (number) The index of the question.
    @param selectedAnswer (string) The answer text submitted.
    @return (boolean) True if correct, false otherwise.
]=]
function QuestionAssignment.IsCorrectAnswer(player, questionIndex, selectedAnswer)
	ValidatePlayer(player)
	assert(type(questionIndex) == "number", "[QuestionAssignment] Invalid question index")
	assert(type(selectedAnswer) == "string", "[QuestionAssignment] Invalid answer")

	local info = GetPlayerInfo(player)
	if not info then
		return false
	end

	local question = info.questions[questionIndex]
	if not question then
		return false
	end

	return IsCorrectAnswerForQuestion(question, selectedAnswer)
end

--[=[
    Adds a strike to the player and fires threshold signal if exceeded.

    @param player (Player) The player receiving a strike.
]=]
function QuestionAssignment.AddStrike(player)
	ValidatePlayer(player)

	local info = GetPlayerInfo(player)
	if info then
		info.strikes += 1
		if info.strikes >= QuestionAssignment.MaxStrikes then
			QuestionAssignment.OnStrikeThresholdMet:Fire(player)
		end
	end
end

--[=[
    Records a player's response and validates its integrity.
    Optimized to calculate correctness once and store result.
    Prevents overwriting of previously answered questions.

    @param player (Player) The player submitting the response.
    @param questionIndex (number) The index of the question being answered.
    @param selectedAnswer (string) The answer text selected by the player.
    @return (string) "success" if valid, "spoofed" if validation fails.
    @throws Error if parameters are invalid or player data is missing.
]=]
function QuestionAssignment.AddResponse(player, questionIndex, selectedAnswer)
	ValidatePlayer(player)
	assert(type(questionIndex) == "number", "[QuestionAssignment] Invalid question index")
	assert(type(selectedAnswer) == "string", "[QuestionAssignment] SelectedAnswer must be a string")

	local info, spoofResult = GetValidatedPlayerInfo(player, "playerData does not exist.")
	if not info then
		return spoofResult
	end

	if info.responses[questionIndex] then
		return Spoof(player, "Attempted to overwrite previous answer.")
	end

	if info.currentQuestionIndex ~= questionIndex then
		return Spoof(player, "Answered questions out of order.")
	end

	local question = info.questions[questionIndex]
	if not question or not IsValidAnswer(question, selectedAnswer) then
		return Spoof(player, "Submitted an invalid answer choice.")
	end

	local isCorrect = IsCorrectAnswerForQuestion(question, selectedAnswer)

	info.responses[questionIndex] = {
		answer = selectedAnswer,
		correct = isCorrect,
	}

	if isCorrect then
		info.correctCount += 1
	end

	info.currentQuestionIndex += 1

	return "success"
end

--[=[
    Removes a player's data from the system.

    @param player (Player) The player to remove.
]=]
function QuestionAssignment.RemovePlayer(player)
	ValidatePlayer(player)
	PlayerData[player.UserId] = nil
end

--[=[
    Grades a player's responses and returns the number of correct and incorrect answers.
    Optimized to use pre-calculated correctness values.

    @param player (Player) The player whose responses are being graded.
    @return (number, number | string) Correct and incorrect counts, or "spoofed" if grading fails.
]=]
function QuestionAssignment.GradeApplication(player)
	ValidatePlayer(player)

	local info, spoofResult = GetValidatedPlayerInfo(player, "playerData does not exist during grading.")
	if not info then
		return spoofResult
	end

	local questions = info.questions
	local responses = info.responses

	if #responses ~= #questions then
		warn("[QuestionAssignment]: Premature grading attempt.")
		return Spoof(player, "Attempted to grade before all questions were answered.")
	end

	local correct = info.correctCount
	local incorrect = #questions - correct

	return correct, incorrect
end

return QuestionAssignment
