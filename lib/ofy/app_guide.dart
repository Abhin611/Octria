/// What Ofy knows about Octria itself: how each thing is done, in words for
/// the chat and as a guide it can walk someone through on screen. The same
/// list is given to the model, so its answers match what the app really does.
library;

/// One moment of a guide: what to point at, and what to say.
class GuideStep {
  const GuideStep(
    this.target,
    this.say, {
    this.prepare,
    this.optional = false,
    this.doIt,
    this.args = const {},
  });

  /// What Ofy does to carry this step out itself while showing it, by the
  /// screen's action id, such as `open-classroom`. Without one, the step is
  /// only pointed at.
  final String? doIt;

  /// What [doIt] needs. `{classroom}` and `{step}` are filled from what the
  /// person asked about.
  final Map<String, String> args;

  /// The named place on screen to highlight, such as `menu:Files`.
  final String target;
  final String say;

  /// Something the screen can do first to bring [target] into view, such as
  /// opening the person's next step.
  final String? prepare;

  /// Skipped when the target isn't on this screen, such as the More button
  /// on a wide screen where the menu is already showing.
  final bool optional;
}

/// How to do one thing in Octria.
class HowTo {
  const HowTo({
    required this.id,
    required this.title,
    required this.answer,
    required this.words,
    this.steps = const [],
  });

  final String id;
  final String title;

  /// The answer in the chat, in plain words.
  final String answer;

  /// Words that suggest someone is asking about this, for when there's no
  /// model to ask.
  final List<String> words;

  /// The guide on screen. Empty when there's nothing to point at.
  final List<GuideStep> steps;
}

const _openClassroom = GuideStep(
  'classroom-card',
  'First, open the classroom.',
  optional: true,
  doIt: 'open-classroom',
  args: {'name': '{classroom}'},
);
const _openMenu = GuideStep(
  'classroom:more',
  'Open More, the classroom’s menu.',
  optional: true,
  doIt: 'show-more',
);
const _openStep = GuideStep(
  'step:panel',
  'This is your step.',
  prepare: 'open-my-step',
  optional: true,
);

const List<HowTo> howTos = [
  HowTo(
    id: 'add-file-to-step',
    title: 'Add a file to a step',
    words: ['file', 'upload', 'attach', 'pdf', 'drive', 'document'],
    answer:
        'Open the step, then under Files tap Add a file from your device. It '
        'goes into an Octria folder in your own Google Drive, and everyone in '
        'the classroom can open it from the step. Only the step’s owner can '
        'add files to it. For files for the whole classroom, use More, then '
        'Files.',
    steps: [
      _openClassroom,
      _openStep,
      GuideStep('step:add-file', 'Tap Add a file from your device.'),
    ],
  ),
  HowTo(
    id: 'add-step',
    title: 'Add a step',
    words: ['add a step', 'new step', 'create a step', 'add step', 'task'],
    answer:
        'In a classroom, tap the + beside the map controls, then give the step '
        'a name, a phase, an owner and dates. You need at least one phase '
        'first. Ofy can also add steps for you: More, then Add to the plan '
        'with Ofy.',
    steps: [
      _openClassroom,
      GuideStep('classroom:add-step', 'Tap + to add a step.'),
    ],
  ),
  HowTo(
    id: 'draft-plan',
    title: 'Let Ofy draft or add to the plan',
    words: ['draft', 'plan', 'generate', 'ai plan', 'make a plan', 'roadmap'],
    answer:
        'In a classroom, open More and tap Draft a plan with Ofy (or Add to '
        'the plan with Ofy once there are steps). Answer a few questions, '
        'untick anything you don’t want, and add it. Dates are worked out from '
        'the hours and your hours per week.',
    steps: [
      _openClassroom,
      _openMenu,
      GuideStep(
        'menu:Draft a plan with Ofy',
        'Tap Draft a plan with Ofy.',
        optional: true,
      ),
      GuideStep(
        'menu:Add to the plan with Ofy',
        'Tap Add to the plan with Ofy.',
        optional: true,
      ),
    ],
  ),
  HowTo(
    id: 'mark-done',
    title: 'Mark a step done',
    words: ['done', 'finish', 'complete', 'mark'],
    answer:
        'Open your step and tap Mark done (on a phone, slide it once you’ve started). If '
        'the classroom needs approval, it goes to the master to approve.',
    steps: [
      _openClassroom,
      _openStep,
      GuideStep('step:done', 'Tap or slide this to mark the step done.'),
    ],
  ),
  HowTo(
    id: 'add-dependency',
    title: 'Make one step need another',
    words: ['depend', 'dependency', 'needs', 'link', 'before', 'blocked'],
    answer:
        'Open the step and under Needs tap Add a step it needs, then pick the '
        'step that must be finished first. On a computer you can also drag '
        'the small handle on a step onto another. Octria refuses links that '
        'would go round in a circle.',
    steps: [
      _openClassroom,
      _openStep,
      GuideStep('step:add-need', 'Tap Add a step it needs.'),
    ],
  ),
  HowTo(
    id: 'hand-over',
    title: 'Hand a step to someone else',
    words: ['hand over', 'handover', 'reassign', 'give my step', 'owner'],
    answer:
        'Open your step and tap the person under Owner. The master agrees '
        'first, then that person accepts or declines. Everyone can see '
        'handovers in More, then Handovers.',
    steps: [
      _openClassroom,
      _openStep,
      GuideStep('step:owner', 'Tap who should take it over.'),
    ],
  ),
  HowTo(
    id: 'study-material',
    title: 'Add a study material to a step',
    words: ['study material', 'material', 'link', 'video', 'note', 'resource'],
    answer:
        'Open your step and under Study materials tap Add, then paste a link, '
        'a video or a repository, or write a note. Only you see the study '
        'materials on your own steps.',
    steps: [
      _openClassroom,
      _openStep,
      GuideStep('step:add-material', 'Tap here to add a study material.'),
    ],
  ),
  HowTo(
    id: 'suggest',
    title: 'Suggest a change to someone’s step',
    words: ['suggest', 'suggestion', 'idea', 'feedback'],
    answer:
        'Open their step and tap Suggest a change. It’s private to the two of '
        'you unless either of you makes it public, and only they can accept '
        'it.',
    steps: [
      _openClassroom,
      GuideStep(
        'step:suggest',
        'Tap Suggest a change.',
        prepare: 'open-any-step',
      ),
    ],
  ),
  HowTo(
    id: 'invite',
    title: 'Invite people to a classroom',
    words: ['invite', 'join', 'code', 'add people', 'members', 'friend'],
    answer:
        'In a classroom open More, then Members and invite code. Share the '
        'code or the link; people join from Add a classroom, then Join with a '
        'code. A classroom holds up to 10 people.',
    steps: [
      _openClassroom,
      _openMenu,
      GuideStep('menu:Members and invite code', 'Tap Members and invite code.'),
    ],
  ),
  HowTo(
    id: 'class-chat',
    title: 'Talk to the whole class',
    words: ['class chat', 'chat', 'message', 'talk', 'announce'],
    answer:
        'In a classroom open More, then Class chat. You can also send a '
        'suggestion for everyone, which people mark done when they’ve done it.',
    steps: [
      _openClassroom,
      _openMenu,
      GuideStep('menu:Class chat', 'Tap Class chat.'),
    ],
  ),
  HowTo(
    id: 'private-chat',
    title: 'Chat privately with someone',
    words: ['private chat', 'dm', 'direct message', 'group chat'],
    answer:
        'In a classroom open More, then Private chats, or tap a person’s '
        'round icon beside their lane on the map. New group chat starts a '
        'chat with several people.',
    steps: [
      _openClassroom,
      _openMenu,
      GuideStep('menu:Private chats', 'Tap Private chats.'),
    ],
  ),
  HowTo(
    id: 'files',
    title: 'Open the classroom’s files',
    words: ['files', 'library', 'shared files'],
    answer:
        'In a classroom open More, then Files. Each file stays in the Google '
        'Drive of whoever added it; you choose whether everyone in the '
        'classroom can open it or only you.',
    steps: [_openClassroom, _openMenu, GuideStep('menu:Files', 'Tap Files.')],
  ),
  HowTo(
    id: 'practice',
    title: 'Find practice sites',
    words: [
      'practice',
      'mock interview',
      'leetcode',
      'questions',
      'exam practice',
    ],
    answer:
        'In a classroom open More, then Practice, for mock interview sites, '
        'question banks and coding practice suggested for your kind of task.',
    steps: [
      _openClassroom,
      _openMenu,
      GuideStep('menu:Practice', 'Tap Practice.'),
    ],
  ),
  HowTo(
    id: 'show-picture',
    title: 'Show Ofy a screenshot or picture',
    words: [
      'screenshot',
      'picture',
      'photo',
      'look at this',
      'what is this',
      'see my screen',
      'image',
    ],
    answer:
        'Open my chat and tap the picture button beside the box. Choose '
        '“The screen behind this chat” to show me where you are in Octria, '
        'or pick a picture from your device, such as an error, a question '
        'paper or a diagram. Then ask your question, or just send it and '
        'I’ll say what it shows.',
  ),
  HowTo(
    id: 'board-ofy',
    title: 'Get Ofy to help with a Kanvas board',
    words: [
      'summarise the board',
      'summarize the board',
      'board summary',
      'what is missing',
      'turn the board into steps',
      'kanvas ofy',
    ],
    answer:
        'Open a board in Kanvas and tap the sparkle button at the top. I '
        'read the words on the board and can summarise it, suggest what’s '
        'missing, or turn it into ordered steps. You can put my answer on '
        'the board as notes or a checklist.',
  ),
  HowTo(
    id: 'share-out',
    title: 'Share work out by skills',
    words: [
      'skills',
      'assign by skill',
      'who should do',
      'share out',
      'split the work',
      'divide the work',
      'resume',
    ],
    answer:
        'Each person adds their skills under Profile, then Edit profile; I '
        'can read them from a resume. Then the master or a co-master opens '
        'More in the classroom and taps Share out by skills. Steps that '
        'haven’t started go to whoever suits them best, with the hours kept '
        'even, and nothing changes until it’s applied.',
    steps: [
      _openClassroom,
      _openMenu,
      GuideStep('menu:Share out by skills', 'Tap Share out by skills.'),
    ],
  ),
  HowTo(
    id: 'replan',
    title: 'Re-plan when I fall behind',
    words: [
      'replan',
      're-plan',
      'behind',
      'falling behind',
      'overdue',
      'catch up',
      'new deadline',
      'reschedule',
    ],
    answer:
        'In a classroom open More, then Re-plan. Octria lays out what’s left '
        'again from today and shows whether it still fits the deadline. If '
        'it doesn’t, you can give it more hours, move the deadline, or ask '
        'me what to shorten or leave out. You see every step that moves '
        'before anything changes.',
    steps: [
      _openClassroom,
      _openMenu,
      GuideStep('menu:Re-plan', 'Tap Re-plan.'),
    ],
  ),
  HowTo(
    id: 'find-resources',
    title: 'Find things to read or watch for a step',
    words: [
      'resources',
      'find material',
      'what to read',
      'what to watch',
      'tutorial',
      'video for',
      'study material',
    ],
    answer:
        'Open one of your steps and, under Study materials, tap Find with '
        'Ofy. I search the web for that step and list what I find; keep the '
        'ones you want and they join the step’s study materials.',
  ),
  HowTo(
    id: 'mock-interview',
    title: 'Take a mock interview',
    words: [
      'interview',
      'mock interview',
      'oral',
      'viva',
      'open questions',
      'harder questions',
      'easier questions',
    ],
    answer:
        'In a classroom open More, then Practice. Choose a step, a phase or '
        'the whole plan, pick Easier, Standard or Harder, then tap Mock '
        'interview. I ask a few open questions; you answer in your own '
        'words, typed or spoken, and I mark each one and say what would '
        'make it stronger.',
    steps: [
      _openClassroom,
      _openMenu,
      GuideStep('menu:Practice', 'Tap Practice.'),
    ],
  ),
  HowTo(
    id: 'results',
    title: 'See my test results',
    words: [
      'results',
      'score',
      'scores',
      'marks',
      'how did i do',
      'test history',
    ],
    answer:
        'Every practice set and mock test you finish is saved, with the '
        'questions you missed. In a classroom open More, then Practice, then '
        'My results. Only you see them, and your next practice on the same '
        'thing comes back to what you missed.',
    steps: [
      _openClassroom,
      _openMenu,
      GuideStep('menu:Practice', 'Tap Practice, then My results.'),
    ],
  ),
  HowTo(
    id: 'calendar',
    title: 'Add steps to my calendar',
    words: [
      'calendar',
      'google calendar',
      'add to calendar',
      'ics',
      'outlook',
      'schedule',
    ],
    answer:
        'In a classroom open More, then Add to calendar, to get your '
        'unfinished steps as a calendar file: each goes on the day it’s due. '
        'For one step, open it and tap the calendar button at the top to '
        'start an event in Google Calendar. The Timeline tab has the same '
        'button for every classroom at once.',
    steps: [
      _openClassroom,
      _openMenu,
      GuideStep('menu:Add to calendar', 'Tap Add to calendar.'),
    ],
  ),
  HowTo(
    id: 'reminders',
    title: 'Turn on reminders',
    words: [
      'reminder',
      'reminders',
      'remind me',
      'notify',
      'notification when due',
      'alert',
    ],
    answer:
        'Open Profile and switch Reminders on. On a phone, Octria then '
        'reminds you the day before a step is due, the day it’s due, and the '
        'day after if it slips, even when the app is closed. In a browser it '
        'tells you what’s due once a day when you open Octria.',
  ),
  HowTo(
    id: 'create-classroom',
    title: 'Create a classroom',
    words: ['create a classroom', 'new classroom', 'start a classroom'],
    answer:
        'On the dashboard tap the + (Add a classroom), then Create a '
        'classroom. Give it a name, choose the type of task and whether it’s '
        'a group or just you, and optionally a deadline and hours per week.',
    steps: [GuideStep('home:add', 'Tap + to add a classroom.')],
  ),
  HowTo(
    id: 'join-classroom',
    title: 'Join a classroom',
    words: ['join a classroom', 'invite code', 'join with a code'],
    answer:
        'On the dashboard tap the + (Add a classroom), then Join with a code, '
        'and type the 6-character code you were given.',
    steps: [GuideStep('home:add', 'Tap + to add a classroom.')],
  ),
  HowTo(
    id: 'kanvas-board',
    title: 'Make a Kanvas board',
    words: ['kanvas', 'board', 'canvas', 'draw', 'whiteboard', 'sticky'],
    answer:
        'Open the Kanvas tab and tap New board. Draw, add sticky notes, text, '
        'checklists, boxes, arrows, links, and images, PDFs or videos from '
        'your Drive. Boards are private until you share them.',
    steps: [
      GuideStep(
        'tab:kanvas',
        'Open the Kanvas tab.',
        doIt: 'switch-tab',
        args: {'tab': 'kanvas'},
      ),
      GuideStep('kanvas:new', 'Tap New board.'),
    ],
  ),
  HowTo(
    id: 'theme',
    title: 'Switch between light and dark',
    words: ['dark', 'light', 'theme', 'background', 'night'],
    answer:
        'Tap the sun or moon button at the top of the dashboard or a '
        'classroom.',
    steps: [GuideStep('theme', 'Tap this to switch the background.')],
  ),
  HowTo(
    id: 'important',
    title: 'See what’s waiting on you',
    words: ['important', 'waiting', 'accept', 'requests', 'pending'],
    answer:
        'The Important button on the dashboard, with a red number, lists '
        'everything waiting for you to accept: handovers, offered boards and '
        'study materials, and suggestions.',
    steps: [GuideStep('home:important', 'Tap Important.')],
  ),
  HowTo(
    id: 'views',
    title: 'See the plan as a timeline or list',
    words: ['timeline', 'list view', 'gantt', 'view'],
    answer:
        'In a classroom, switch between Flowspace (the map), Timeline (dates '
        'to scale) and List at the top of the screen.',
    steps: [_openClassroom, GuideStep('classroom:views', 'Switch views here.')],
  ),
];

/// The how-to a question is most likely about, when there's no model to ask.
HowTo? guessHowTo(String question) {
  final q = question.toLowerCase();
  HowTo? best;
  var bestScore = 0;
  for (final h in howTos) {
    var score = 0;
    for (final w in h.words) {
      if (q.contains(w)) score += w.contains(' ') ? 3 : 2;
    }
    for (final w in h.title.toLowerCase().split(' ')) {
      if (w.length > 3 && q.contains(w)) score += 1;
    }
    if (score > bestScore) {
      bestScore = score;
      best = h;
    }
  }
  return bestScore >= 2 ? best : null;
}

HowTo? howToById(String? id) => howTos.where((h) => h.id == id).firstOrNull;

/// The whole guide as text, for the model.
String get guideForModel =>
    [for (final h in howTos) '[${h.id}] ${h.title}: ${h.answer}'].join('\n');
