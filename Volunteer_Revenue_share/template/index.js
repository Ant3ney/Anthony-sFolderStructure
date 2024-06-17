const example = [
  {
    username: "Krolog",
    game: "",
  },
  {
    username: "SaintlyDemonic",
    game: "",
  },
  {
    username: "boltthrower666:",
    game: "",
  },
  {
    username: "Aviana",
    game: "Silverdale: Winter Champion",
  },
  {
    username: "Jan Vogelsang",
    game: "",
  },
  {
    username: "Kerremanske",
    game: "",
  },
  {
    username: "👑DaGrinch👑",
    game: "",
  },
  {
    username: "Marshall Hawke",
    game: "",
  },
  {
    username: "𝔍𝔍",
    game: "",
  },
  {
    username: "TheSuperSussySigmaImposter™",
    game: "",
  },
  {
    username: "SkinnyBruv",
    game: "",
  },
  {
    username: "Rafig",
    game: "",
  },
];

const formatted = example.map((contact, i) => {
  const { username, game } = contact;
  return `${i !== 0 ? "\n\n\n" : ""}\n\n\n
  Username: ${username}

Hello ${username}, 

    I'm really enthusiastic about the possibility of joining your team and elevating your game${
      game ? " " + game : ""
    }. My approach is to treat this venture with the dedication and professionalism of a paid role, underscoring my commitment to game development. My passion for creating video games transcends the need for monetary compensation. I'm here for the love of the craft and the potential to create something extraordinary.

    One aspect that excites me about team collaborations is the opportunity to leverage collective skills and manpower, allowing us to achieve grander and more complex creations. This belief drives my interest in becoming a part of what you're building.

    Currently, I'm not in a position to commit immediately but I'm keen to understand more about your vision and the team dynamics. Could we arrange a conversation to dive deeper into the details of your project? I'm eager to learn about the game's concept, the progress you've made so far, and how you're utilizing Unreal Engine for development.

    Here's my Calendly link for scheduling a chat at your convenience: Schedule a Call.
https://calendly.com/anthonycavuoti/scheduleinterview

    Also, feel free to explore my portfolio to get a sense of my work and experiences in game development: Anthony Cavuoti's GameDev Portfolio.
https://gamedev.anthonycavuoti.com

    Looking forward to the possibility of contributing to your project and learning more about your team.

Best,
Anthony Cavuoti

  `;
});

document.getElementById("result").innerHTML = formatted.join("<br><br>");
