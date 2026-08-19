export function Spinner({ label }: { label?: string }) {
  return (
    <div className="spinner-box" role="status" aria-live="polite">
      <span className="spinner" aria-hidden="true" />
      {label && <span className="spinner-label">{label}</span>}
    </div>
  );
}

export function FullPageSpinner({ label }: { label?: string }) {
  return (
    <div className="spinner-page">
      <Spinner label={label} />
    </div>
  );
}
