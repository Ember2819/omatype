.pragma library

// The typing test as plain functions over a plain state object, with no QML
// in it, so tests/engine.test.js can run it under node. The QML only draws
// the state and feeds it keys.

var EXTRA_LIMIT = 19;   // Letters a word may be typed past its end.

var WORDS = (
    "the be of and a to in he have it that for they I with as not on she at by this we you do but from or which " +
    "one would all will there say who make when can more if no man out other so what time up go about than into " +
    "could state only new year some take come these know see use get like then first any work now may such give " +
    "over think most even find day also after way many must look before great back through long where much " +
    "should well people down own just because good each those feel seem how high too place little world very " +
    "still nation hand old life tell write become here show house both between need mean call develop under " +
    "last right move thing general school never same another begin while number part turn real leave might want " +
    "point form off child few small since against ask late home interest large person end open public follow " +
    "during present without again hold govern around possible head consider word program problem however lead " +
    "system set order eye plan run keep face fact group play stand increase early course change help line city " +
    "put close case force meet once water upon war build hear light unite live every country bring center let " +
    "side try provide continue name certain power pay result question study woman member until far night always " +
    "service away report something company week church toward start social room figure nature though young less " +
    "enough almost read include president nothing yes best better big black body book boy car clear color dark " +
    "dream earth east easy fall family fire food free friend game girl green ground hair half heart heavy idea " +
    "image king land language letter list love machine market mind money month moon morning mother music north " +
    "paper picture piece plant poor quiet rain red river road rock rule sea ship simple sing sister sleep slow " +
    "snow song sound south spring star story street strong summer sun table teacher tree true voice wall warm " +
    "wind window winter wood yellow"
).split(" ");

function copyWords() { return WORDS.slice(); }

// A generator of words, one at a time, so a time test can ask for more as the
// writer runs through them. Punctuation capitalises after a stop and
// sprinkles commas, stops, quotes, and the like; numbers swaps in digits.
function createGenerator(options, rng) {
    var random = rng || Math.random;
    var opts = options || {};
    var capitalizeNext = true;
    var lastWord = "";
    var quoteOpen = false;

    function pick() {
        var word;
        do {
            word = WORDS[Math.floor(random() * WORDS.length)];
        } while (word === lastWord);
        return word;
    }

    function digits() {
        var length = 1 + Math.floor(random() * 4);
        var out = "";
        for (var i = 0; i < length; ++i)
            out += String(Math.floor(random() * 10));
        // No leading zero on a number longer than one digit.
        if (out.length > 1 && out.charAt(0) === "0")
            out = String(1 + Math.floor(random() * 9)) + out.substring(1);
        return out;
    }

    return function next() {
        var word;
        if (opts.numbers && random() < 0.12) {
            word = digits();
        } else {
            word = pick();
            lastWord = word;
        }

        if (!opts.punctuation)
            return word;

        var isNumber = /^[0-9]+$/.test(word);
        if (capitalizeNext && !isNumber) {
            word = word.charAt(0).toUpperCase() + word.substring(1);
            capitalizeNext = false;
        }

        var roll = random();
        if (!isNumber && !quoteOpen && roll < 0.04) {
            word = "\"" + word;
            quoteOpen = true;
        } else if (quoteOpen && roll < 0.25) {
            word = word + "\"";
            quoteOpen = false;
        } else if (roll < 0.10) {
            word += ",";
        } else if (roll < 0.17) {
            word += ".";
            capitalizeNext = true;
        } else if (roll < 0.19) {
            word += "?";
            capitalizeNext = true;
        } else if (roll < 0.21) {
            word += "!";
            capitalizeNext = true;
        } else if (roll < 0.23) {
            word += ";";
        } else if (roll < 0.25) {
            word += ":";
        }
        return word;
    };
}

function generate(count, options, rng) {
    var next = createGenerator(options, rng);
    var out = [];
    for (var i = 0; i < count; ++i)
        out.push(next());
    return out;
}

function createState(words) {
    var state = {
        words: words.slice(),
        typed: [],
        index: 0,
        finished: false,
        keystrokes: 0,
        correctKeystrokes: 0,
        incorrectKeystrokes: 0,
        lastSampleSec: 0,
        lastSampleTyped: 0,
        lastSampleErrors: 0,
        samples: []
    };
    for (var i = 0; i < words.length; ++i)
        state.typed.push("");
    return state;
}

function appendWords(state, more) {
    for (var i = 0; i < more.length; ++i) {
        state.words.push(more[i]);
        state.typed.push("");
    }
}

function isLastWord(state) {
    return state.index >= state.words.length - 1;
}

// A letter. `endOnLastWord` is true for a words test, which ends as the last
// word is typed out; a time test never runs out of words.
function typeChar(state, ch, endOnLastWord) {
    if (state.finished)
        return false;

    var word = state.words[state.index];
    var typed = state.typed[state.index];
    if (typed.length >= word.length + EXTRA_LIMIT)
        return false;

    state.keystrokes += 1;
    if (typed.length < word.length && word.charAt(typed.length) === ch)
        state.correctKeystrokes += 1;
    else
        state.incorrectKeystrokes += 1;

    state.typed[state.index] = typed + ch;
    if (endOnLastWord && isLastWord(state) && typed.length + 1 >= word.length)
        state.finished = true;
    return true;
}

// Space moves on to the next word. It does nothing on an empty word, so a
// stray space cannot skip a word that has not been started.
function space(state, endOnLastWord) {
    if (state.finished || state.typed[state.index].length === 0)
        return false;

    var correct = state.typed[state.index] === state.words[state.index];
    state.keystrokes += 1;
    if (correct)
        state.correctKeystrokes += 1;
    else
        state.incorrectKeystrokes += 1;

    if (endOnLastWord && isLastWord(state)) {
        state.finished = true;
        return true;
    }

    state.index += 1;
    return true;
}

function previousWordIsWrong(state) {
    return state.index > 0
        && state.typed[state.index - 1] !== state.words[state.index - 1];
}

// Backspace. At the start of a word it steps back into the word before, but
// only when that word was wrong: a word typed right stays done.
function backspace(state) {
    if (state.finished)
        return false;

    var typed = state.typed[state.index];
    if (typed.length > 0) {
        state.typed[state.index] = typed.substring(0, typed.length - 1);
        return true;
    }
    if (previousWordIsWrong(state)) {
        state.index -= 1;
        return true;
    }
    return false;
}

// Ctrl+Backspace clears the word being typed, or when it is empty, steps back
// into the wrong word before it and clears that.
function deleteWord(state) {
    if (state.finished)
        return false;

    if (state.typed[state.index].length > 0) {
        state.typed[state.index] = "";
        return true;
    }
    if (previousWordIsWrong(state)) {
        state.index -= 1;
        state.typed[state.index] = "";
        return true;
    }
    return false;
}

function totalTypedChars(state) {
    var total = 0;
    for (var i = 0; i <= state.index && i < state.typed.length; ++i)
        total += state.typed[i].length + (i < state.index ? 1 : 0);
    return total;
}

// Characters sorted the way the results screen lists them. `ended` says the
// test is over, which is when letters left out of the last word count as missed.
function charCounts(state, ended) {
    var counts = { correct: 0, incorrect: 0, extra: 0, missed: 0, wordChars: 0 };
    for (var i = 0; i <= state.index && i < state.words.length; ++i) {
        var word = state.words[i];
        var typed = state.typed[i];
        var committed = i < state.index;
        if (!committed && typed.length === 0)
            break;

        for (var j = 0; j < typed.length; ++j) {
            if (j >= word.length)
                counts.extra += 1;
            else if (typed.charAt(j) === word.charAt(j))
                counts.correct += 1;
            else
                counts.incorrect += 1;
        }
        if (committed || ended)
            counts.missed += Math.max(0, word.length - typed.length);

        // Only words typed right count towards the speed, space included; the
        // word in progress counts for as far as it is right.
        if (committed) {
            if (typed === word)
                counts.wordChars += word.length + 1;
        } else if (word.indexOf(typed) === 0) {
            counts.wordChars += typed.length;
        }
    }
    return counts;
}

function minutes(elapsedSeconds) {
    return Math.max(elapsedSeconds, 0.001) / 60;
}

function wpm(state, elapsedSeconds) {
    return charCounts(state, false).wordChars / 5 / minutes(elapsedSeconds);
}

function rawWpm(state, elapsedSeconds) {
    return totalTypedChars(state) / 5 / minutes(elapsedSeconds);
}

function accuracy(state) {
    if (state.keystrokes === 0)
        return 100;
    return state.correctKeystrokes / state.keystrokes * 100;
}

// One point for the results graph: speed so far, raw speed over the stretch
// since the last point, and the mistakes made in it.
function sample(state, elapsedSeconds) {
    var span = elapsedSeconds - state.lastSampleSec;
    if (span <= 0.0001)
        return null;

    var typed = totalTypedChars(state);
    var point = {
        second: Math.round(elapsedSeconds * 10) / 10,
        wpm: wpm(state, elapsedSeconds),
        raw: Math.max(0, (typed - state.lastSampleTyped) / 5 / minutes(span)),
        errors: state.incorrectKeystrokes - state.lastSampleErrors
    };
    state.lastSampleSec = elapsedSeconds;
    state.lastSampleTyped = typed;
    state.lastSampleErrors = state.incorrectKeystrokes;
    state.samples.push(point);
    return point;
}

// How steady the typing was, 0 to 100, from the spread of the raw speed
// between samples. A tanh squash of the coefficient of variation, as
// Monkeytype does.
function consistency(samples) {
    if (samples.length < 2)
        return 100;
    var values = samples.map(function(s) { return s.raw; });
    var mean = values.reduce(function(a, b) { return a + b; }, 0) / values.length;
    if (mean <= 0)
        return 0;
    var variance = values.reduce(function(a, v) { return a + (v - mean) * (v - mean); }, 0)
                   / values.length;
    var cv = Math.sqrt(variance) / mean;
    var x = cv + Math.pow(cv, 3) / 3 + Math.pow(cv, 5) / 5;
    var tanh = (Math.exp(2 * x) - 1) / (Math.exp(2 * x) + 1);
    return Math.max(0, Math.min(100, (1 - tanh) * 100));
}

function result(state, elapsedSeconds) {
    sample(state, elapsedSeconds);
    var counts = charCounts(state, true);
    return {
        wpm: wpm(state, elapsedSeconds),
        raw: rawWpm(state, elapsedSeconds),
        accuracy: accuracy(state),
        consistency: consistency(state.samples),
        correct: counts.correct,
        incorrect: counts.incorrect,
        extra: counts.extra,
        missed: counts.missed,
        seconds: elapsedSeconds,
        samples: state.samples.slice()
    };
}

// Tests with different settings are not comparable, so each has its own
// best and its own row in the history.
function configKey(config) {
    return config.mode + ":" + config.amount
        + ":p" + (config.punctuation ? 1 : 0)
        + ":n" + (config.numbers ? 1 : 0);
}
