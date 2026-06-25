--[[
	Entries
	Question pool for QuestionAssignment. Questions are randomly selected and shuffled at runtime.

	Each entry:
	  questionText   string  — shown to the applicant
	  answerOptions  array   — list of { responseText } tables (shuffled before display)
	  correctIndex   number  — 1-based index of the correct answer as written here
]]

return {

	-- EXAMPLE
	{
		questionText = "A customer tells you their order is wrong. What should you do?",
		answerOptions = {
			{ responseText = "Apologize and correct the order as quickly as possible." },
			{ responseText = "Tell them to re-order at the counter." },
			{ responseText = "Ignore it since mistakes happen." },
		},
		correctIndex = 1
	},

}