// orior - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
//
// When the next turn of a frame loop runs. With vsync, once per display refresh. Without it, as soon as the turn
// before has left the main thread, through a message port that the browser does not hold to the refresh. A hidden
// page always waits for the refresh: an uncapped loop never runs in a tab no one sees. The meter counts the turns
// that actually ran, per second, over half-second windows.

EV.uncapped = (() => {
  const channel = new MessageChannel();
  let queued = null;
  channel.port1.onmessage = () => {
    const turn = queued;
    queued = null;
    if (turn) {
      turn(performance.now());
    }
  };
  return (turn) => {
    queued = turn;
    channel.port2.postMessage(0);
  };
})();

EV.nextTurn = (vsync, turn) => (vsync || document.hidden ? requestAnimationFrame(turn) : EV.uncapped(turn));

EV.rateMeter = () => {
  let count = 0;
  let since = performance.now();
  let rate = 0;
  return {
    tick: (now) => {
      count += 1;
      if (now - since >= 500) {
        rate = Math.round((count * 1000) / (now - since));
        count = 0;
        since = now;
      }
      return rate;
    },
    rate: () => rate,
  };
};
