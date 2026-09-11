"use client";

import { Smile, Sun } from "lucide-react";
import ReactConfetti from "react-confetti";

export function IlimSmileGreeting({
  clicks,
  onSmile,
}: {
  clicks: number;
  onSmile: () => void;
}) {
  const remaining = 10 - clicks;

  return (
    <div className="ilim-greeting-overlay" role="dialog" aria-modal="true" aria-labelledby="ilim-greeting-title">
      <ReactConfetti
        className="milestone-confetti-canvas"
        numberOfPieces={180}
        recycle
        gravity={0.08}
        colors={["#ffd166", "#ff9f1c", "#ffffff", "#17a96f", "#4cc9f0"]}
      />
      <section className="ilim-greeting-modal">
        <Sun className="ilim-greeting-sun" aria-hidden="true" />
        <span className="ilim-greeting-kicker">Персонально для тебя</span>
        <h2 id="ilim-greeting-title">Доброе утро, Илим!</h2>
        <p>Утро начинается с твоей улыбки. Улыбнись, чтобы открыть сайт.</p>
        <button className="ilim-smile-button" type="button" onClick={onSmile} autoFocus>
          <Smile aria-hidden="true" />
          Улыбка
        </button>
        <small>
          {remaining === 1
            ? "Осталась последняя улыбка 😊"
            : `Чтобы открыть сайт, нажми «Улыбка» ещё ${remaining} раз`}
        </small>
      </section>
    </div>
  );
}
