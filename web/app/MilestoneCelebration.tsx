"use client";

import { PartyPopper } from "lucide-react";
import ReactConfetti from "react-confetti";

export function MilestoneCelebration({
  clicks,
  total,
  onConfirm,
}: {
  clicks: number;
  total: number;
  onConfirm: () => void;
}) {
  const remaining = 10 - clicks;

  return (
    <div className="milestone-overlay" role="dialog" aria-modal="true" aria-labelledby="milestone-title">
      <ReactConfetti
        className="milestone-confetti-canvas"
        numberOfPieces={480}
        recycle
        gravity={0.1}
        initialVelocityY={18}
        colors={["#ffd166", "#17a96f", "#17437a", "#ef476f", "#9b5de5", "#00bbf9", "#ffffff"]}
      />
      <section className="milestone-modal">
        <div className="milestone-emoji-row" aria-hidden="true">🎈 🎊 🏆 🎊 🎈</div>
        <PartyPopper className="milestone-icon" aria-hidden="true" />
        <span className="milestone-kicker">У нас праздник!</span>
        <h2 id="milestone-title">Мы достигли отметки 1000 осмотров!</h2>
        <strong className="milestone-number">{total}</strong>
        <p>Спасибо всей команде AutoLab. Это наша общая большая победа!</p>
        <button className="btn milestone-confirm" type="button" onClick={onConfirm} autoFocus>
          ОК
        </button>
        <small>
          {remaining === 1
            ? "Последнее нажатие — и праздничное окно закроется 🎉"
            : `Чтобы закрыть праздничное окно, нажмите «ОК» ещё ${remaining} раз 🎉`}
        </small>
      </section>
    </div>
  );
}
