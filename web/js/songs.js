/* Guitar Quest - easy public-domain melodies (traditional / 18th-19th century).
   Pitches are written as they SOUND on the guitar (E4 = open high e string).
   Token: Note+octave[:duration]   durations: w h. h q. q 8. 8 16   (default q)   r = rest */
(function (GQ) {
  'use strict';
  GQ.SONGS = [
    {
      id: 'mary', title: 'Mary Had a Little Lamb', origin: 'Traditional', key: 'C', family: 'major', tempo: 90,
      strings: 'Strings 1-2',
      notes: 'E4 D4 C4 D4 | E4 E4 E4:h | D4 D4 D4:h | E4 G4 G4:h | E4 D4 C4 D4 | E4 E4 E4 E4 | D4 D4 E4 D4 | C4:w',
    },
    {
      id: 'jingle', title: 'Jingle Bells (chorus)', origin: 'J. L. Pierpont, 1857', key: 'C', family: 'major', tempo: 100,
      strings: 'Strings 1-2',
      notes: 'E4 E4 E4:h | E4 E4 E4:h | E4 G4 C4:q. D4:8 | E4:w | F4 F4 F4 F4 | F4 E4 E4 E4:8 E4:8 | E4 D4 D4 E4 | D4:h G4:h |' +
        ' E4 E4 E4:h | E4 E4 E4:h | E4 G4 C4:q. D4:8 | E4:w | F4 F4 F4 F4 | F4 E4 E4 E4:8 E4:8 | G4 G4 F4 D4 | C4:w',
    },
    {
      id: 'ode', title: 'Ode to Joy', origin: 'L. van Beethoven, Symphony No. 9', key: 'C', family: 'major', tempo: 92,
      strings: 'Strings 1-3',
      notes: 'E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | E4:q. D4:8 D4:h |' +
        ' E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | D4:q. C4:8 C4:h |' +
        ' D4 D4 E4 C4 | D4 E4:8 F4:8 E4 C4 | D4 E4:8 F4:8 E4 D4 | C4 D4 G3:h |' +
        ' E4 E4 F4 G4 | G4 F4 E4 D4 | C4 C4 D4 E4 | D4:q. C4:8 C4:h',
    },
    {
      id: 'twinkleG', title: 'Twinkle, Twinkle, Little Star (in G)', origin: 'Traditional', key: 'G', family: 'major', tempo: 96,
      strings: 'Strings 1-3',
      notes: 'G3 G3 D4 D4 | E4 E4 D4:h | C4 C4 B3 B3 | A3 A3 G3:h | D4 D4 C4 C4 | B3 B3 A3:h | D4 D4 C4 C4 | B3 B3 A3:h |' +
        ' G3 G3 D4 D4 | E4 E4 D4:h | C4 C4 B3 B3 | A3 A3 G3:h',
    },
    {
      id: 'twinkleC', title: 'Twinkle, Twinkle, Little Star (low, in C)', origin: 'Traditional', key: 'C', family: 'major', tempo: 96,
      strings: 'Strings 3-5',
      notes: 'C3 C3 G3 G3 | A3 A3 G3:h | F3 F3 E3 E3 | D3 D3 C3:h | G3 G3 F3 F3 | E3 E3 D3:h | G3 G3 F3 F3 | E3 E3 D3:h |' +
        ' C3 C3 G3 G3 | A3 A3 G3:h | F3 F3 E3 E3 | D3 D3 C3:h',
    },
  ];
})(typeof window !== 'undefined' ? (window.GQ = window.GQ || {}) : (globalThis.GQ = globalThis.GQ || {}));
