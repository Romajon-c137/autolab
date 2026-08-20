"use client";

import { ChangeEvent, PointerEvent, ReactNode, useEffect, useMemo, useRef, useState } from "react";
import { ApplicationFormState, buildApplicationDocument } from "./application-document";

type FormState = ApplicationFormState;

const STORAGE_KEY = "autolab_form";

const emptyForm: FormState = {
  applicant: "",
  inn: "",
  phone: "+996",
  vehicleName: "",
  plateNumber: "",
  year: "2026",
  vin: "",
};

function loadForm(): FormState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return emptyForm;
    return { ...emptyForm, ...JSON.parse(raw) };
  } catch {
    return emptyForm;
  }
}

function saveForm(form: FormState) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(form));
  } catch {}
}

function clearForm() {
  try {
    localStorage.removeItem(STORAGE_KEY);
  } catch {}
}

const brandSuggestions = [
  "Toyota",
  "Chevrolet",
  "Mercedes-Benz",
  "BMW",
  "Hyundai",
  "Kia",
  "Lexus",
  "Honda",
  "Nissan",
  "Volkswagen",
  "Audi",
  "Mazda",
  "Subaru",
  "Mitsubishi",
  "Ford",
  "Daewoo",
  "Lada",
];

const platePrefixes = Array.from({ length: 10 }, (_, index) => `${String(index + 1).padStart(2, "0")}KG`);
const years = Array.from({ length: 47 }, (_, index) => String(2026 - index));

const requiredFields: Array<keyof FormState> = [
  "applicant",
  "inn",
  "phone",
  "vehicleName",
  "plateNumber",
  "year",
  "vin",
];

export default function Page() {
  const [form, setForm] = useState<FormState>(emptyForm);
  const [step, setStep] = useState<1 | 2 | 3 | 4>(1);
  const [submitted, setSubmitted] = useState(false);
  const [scanStatus, setScanStatus] = useState("");
  const [scanError, setScanError] = useState("");
  const [scanWarning, setScanWarning] = useState("");
  const [scanLoading, setScanLoading] = useState(false);
  const [signatureData, setSignatureData] = useState("");
  const [submitStatus, setSubmitStatus] = useState("");
  const [submitError, setSubmitError] = useState("");
  const [submitLoading, setSubmitLoading] = useState(false);
  const [matchedInspectionId, setMatchedInspectionId] = useState<number | null>(null);
  const [showInnHint, setShowInnHint] = useState(false);
  useEffect(() => {
    setForm(loadForm());
  }, []);

  useEffect(() => {
    saveForm(form);
  }, [form]);

  const scanInputRef = useRef<HTMLInputElement | null>(null);
  const signatureCanvasRef = useRef<HTMLCanvasElement | null>(null);
  const drawingRef = useRef(false);

  const completed = useMemo(() => {
    const filled = requiredFields.filter((key) => isFieldComplete(key, form)).length + (signatureData ? 1 : 0);
    return Math.round((filled / (requiredFields.length + 1)) * 100);
  }, [form, signatureData]);

  const clientComplete = isFieldComplete("applicant", form) && isFieldComplete("inn", form) && isFieldComplete("phone", form);
  const vehicleComplete =
    isFieldComplete("vehicleName", form) &&
    isFieldComplete("plateNumber", form) &&
    isFieldComplete("year", form) &&
    isFieldComplete("vin", form);
  const canPreview = clientComplete && vehicleComplete && Boolean(signatureData);

  function updateField(key: keyof FormState) {
    return (event: ChangeEvent<HTMLInputElement | HTMLTextAreaElement | HTMLSelectElement>) => {
      const value = event.target.value;
      setForm((current) => ({
        ...current,
        [key]: key === "vin" || key === "plateNumber" ? value.toUpperCase() : value,
      }));
    };
  }

  function updatePhone(event: ChangeEvent<HTMLInputElement>) {
    const rest = event.target.value.replace(/\D/g, "").replace(/^996/, "").slice(0, 9);
    const groups = rest.match(/.{1,3}/g) ?? [];
    const nextValue = ["+996", ...groups].join(" ").trim();
    setForm((current) => ({ ...current, phone: nextValue }));
  }

  function updateInn(event: ChangeEvent<HTMLInputElement>) {
    const value = event.target.value.replace(/\D/g, "").slice(0, 14);
    setForm((current) => ({ ...current, inn: value }));
  }

  function updateVehicleName(event: ChangeEvent<HTMLInputElement>) {
    const value = event.target.value;
    const selectedBrand = brandSuggestions.find((brand) => brand.toLowerCase() === value.toLowerCase());
    setForm((current) => ({ ...current, vehicleName: selectedBrand ? `${selectedBrand} ` : value }));
  }

  function updatePlateNumber(event: ChangeEvent<HTMLInputElement>) {
    const value = event.target.value.toUpperCase();
    const selectedPrefix = platePrefixes.find((prefix) => prefix === value);
    setForm((current) => ({ ...current, plateNumber: selectedPrefix ? `${selectedPrefix} ` : value }));
  }

  function updateVin(event: ChangeEvent<HTMLInputElement>) {
    const value = event.target.value.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 17);
    setForm((current) => ({ ...current, vin: value }));
  }

  async function scanTechPassport(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0];
    event.target.value = "";
    if (!file) return;

    setScanError("");
    setScanWarning("");
    setScanStatus("Сканируем техпаспорт...");
    setScanLoading(true);

    const requestData = new FormData();
    requestData.append("tech_passport", file);

    try {
      const response = await fetch("/api/scan-tech-passport", {
        method: "POST",
        body: requestData,
      });
      const result = await response.json();
      if (!response.ok || !result.ok) {
        throw new Error(result.error || `HTTP ${response.status}`);
      }

      const data = result.data as Partial<FormState>;
      setForm((current) => ({
        ...current,
        vehicleName: data.vehicleName || current.vehicleName,
        plateNumber: data.plateNumber || current.plateNumber,
        year: data.year || current.year,
        vin: data.vin || current.vin,
      }));
      setScanStatus("Данные из техпаспорта заполнены");
      setScanWarning(
        data.vin
          ? "Обязательно сверьте VIN с техпаспортом перед продолжением."
          : "VIN не удалось распознать полностью. Введите все 17 символов вручную и сверьте их с техпаспортом."
      );
    } catch (error) {
      setScanStatus("");
      setScanWarning("");
      setScanError(error instanceof Error ? error.message : "Не удалось распознать техпаспорт");
    } finally {
      setScanLoading(false);
    }
  }

  function startSignature(event: PointerEvent<HTMLCanvasElement>) {
    drawingRef.current = true;
    event.currentTarget.setPointerCapture(event.pointerId);
    drawSignature(event);
  }

  function drawSignature(event: PointerEvent<HTMLCanvasElement>) {
    if (!drawingRef.current) return;
    const canvas = signatureCanvasRef.current;
    if (!canvas) return;

    const context = canvas.getContext("2d");
    if (!context) return;

    const rect = canvas.getBoundingClientRect();
    const x = ((event.clientX - rect.left) / rect.width) * canvas.width;
    const y = ((event.clientY - rect.top) / rect.height) * canvas.height;

    context.lineWidth = 4;
    context.lineCap = "round";
    context.lineJoin = "round";
    context.strokeStyle = "#21327f";

    if (context.getLineDash().length) context.setLineDash([]);
    context.lineTo(x, y);
    context.stroke();
    context.beginPath();
    context.moveTo(x, y);
  }

  function endSignature() {
    const canvas = signatureCanvasRef.current;
    if (!canvas) return;
    drawingRef.current = false;
    const context = canvas.getContext("2d");
    context?.beginPath();
    setSignatureData(canvas.toDataURL("image/png"));
  }

  function clearSignature() {
    const canvas = signatureCanvasRef.current;
    if (!canvas) return;
    const context = canvas.getContext("2d");
    context?.clearRect(0, 0, canvas.width, canvas.height);
    setSignatureData("");
  }

  async function submitApplication() {
    setSubmitStatus("Ищем совпадение по VIN в базе...");
    setSubmitError("");
    setSubmitLoading(true);

    try {
      const response = await fetch("/api/applications/submit", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ form, signatureData }),
      });
      const result = await response.json();
      if (!response.ok || !result.ok) {
        throw new Error(result.error || `HTTP ${response.status}`);
      }

      const inspectionId = result.inspection?.id ?? null;
      setMatchedInspectionId(inspectionId);
      setSubmitStatus(
        inspectionId
          ? `Совпадение найдено! Заявка прикреплена к осмотру #${inspectionId}`
          : "Совпадение не найдено. Заявка сохранена и будет прикреплена автоматически, как только осмотр появится в системе."
      );
      clearForm();
      setSubmitted(true);
    } catch (error) {
      setSubmitStatus("");
      setSubmitError(error instanceof Error ? error.message : "Не удалось отправить заявку");
    } finally {
      setSubmitLoading(false);
    }
  }

  if (submitted) {
    return (
      <main className="page">
        <div className="success-screen">
          <div className="success-icon">✓</div>
          <h1>Заявка принята</h1>
          <p>
            {matchedInspectionId
              ? `Совпадение найдено: заявка прикреплена к осмотру #${matchedInspectionId}.`
              : "Совпадение по VIN пока не найдено. Заявка сохранена и привяжется автоматически, когда осмотр появится."}
          </p>
        </div>
      </main>
    );
  }

  return (
    <main className="page">
      <section className="workspace">
        <header className="topbar">
          <div>
            <p className="eyebrow">Авто лаборатория</p>
            <h1>Онлайн заявка</h1>
          </div>
          <div className="progress" aria-label={`Заполнено ${completed}%`}>
            <span>{completed}%</span>
            <div>
              <i style={{ width: `${completed}%` }} />
            </div>
          </div>
        </header>

        <div className="content-grid">
          <form className="form-panel">
            <div className="step-tabs" aria-label="Шаги заявки">
              <button type="button" className={step === 1 ? "active" : ""} onClick={() => setStep(1)}>
                1. Клиент
              </button>
              <button type="button" className={step === 2 ? "active" : ""} onClick={() => setStep(2)} disabled={!clientComplete}>
                2. Авто
              </button>
              <button type="button" className={step === 3 ? "active" : ""} onClick={() => setStep(3)} disabled={!clientComplete || !vehicleComplete}>
                3. Подпись
              </button>
              <button type="button" className={step === 4 ? "active" : ""} onClick={() => setStep(4)} disabled={!canPreview}>
                4. Документ
              </button>
            </div>

            {step === 1 ? (
              <div className="step-panel">
                <SectionTitle title="Паспортные данные" />
                <Field
                  label="ФИО"
                  value={form.applicant}
                  onChange={updateField("applicant")}
                  placeholder="Ашимов Илхом ..."
                  autoComplete="name"
                  required
                />
                <Field
                  label="ИНН"
                  value={form.inn}
                  onChange={updateInn}
                  placeholder="14 цифр"
                  type="text"
                  inputMode="numeric"
                  maxLength={14}
                  helper={`${form.inn.length}/14 символов`}
                  error={form.inn.length > 0 && form.inn.length !== 14 ? "ИНН должен состоять из 14 цифр" : ""}
                  onFocus={() => setShowInnHint(true)}
                  onBlur={() => setShowInnHint(false)}
                  ariaDescribedBy="inn-location-hint"
                  required
                />
                {showInnHint ? (
                  <div className="inn-hint" id="inn-location-hint" role="note">
                    <strong>Где найти ИНН</strong>
                    <span>ИНН — это 14-значный персональный номер на обратной стороне ID-карты.</span>
                    <img src="/inn-id-card-hint.png" alt="Место расположения ИНН на обратной стороне ID-карты обведено красным" />
                  </div>
                ) : null}
                <Field
                  label="Номер телефона"
                  value={form.phone}
                  onChange={updatePhone}
                  placeholder="+996 ..."
                  type="tel"
                  inputMode="tel"
                  autoComplete="tel"
                  error={form.phone !== "+996" && !isFieldComplete("phone", form) ? "Номер должен быть в формате +996 555 111 222" : ""}
                  required
                />
                <div className="form-actions">
                  <button type="button" className="primary-button" onClick={() => setStep(2)} disabled={!clientComplete}>
                    Далее
                  </button>
                </div>
              </div>
            ) : step === 2 ? (
              <div className="step-panel">
                <SectionTitle title="Транспортное средство" />
                <input
                  ref={scanInputRef}
                  className="hidden-file"
                  type="file"
                  accept="image/*"
                  capture="environment"
                  onChange={scanTechPassport}
                />
                <button
                  type="button"
                  className="scan-button"
                  onClick={() => scanInputRef.current?.click()}
                  disabled={scanLoading}
                  aria-busy={scanLoading}
                >
                  <span className="scan-button-icon" aria-hidden="true">
                    {scanLoading ? (
                      <span className="scan-spinner" />
                    ) : (
                      <svg viewBox="0 0 24 24" fill="none">
                        <path d="M8.5 5.5 10 3.5h4l1.5 2H19a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-10a2 2 0 0 1 2-2h3.5Z" />
                        <circle cx="12" cy="12.5" r="4" />
                      </svg>
                    )}
                  </span>
                  <span>{scanLoading ? "Распознаём..." : "Сканировать техпаспорт"}</span>
                </button>
                {scanStatus ? <p className="scan-status">{scanStatus}</p> : null}
                {scanError ? <p className="scan-error">{scanError}</p> : null}
                {scanWarning ? <p className="scan-warning">{scanWarning}</p> : null}
                <Field
                  label="Марка авто"
                  value={form.vehicleName}
                  onChange={updateVehicleName}
                  placeholder="Toyota Camry"
                  list="brand-suggestions"
                  required
                />
                <datalist id="brand-suggestions">
                  {brandSuggestions.map((brand) => (
                    <option key={brand} value={brand} />
                  ))}
                </datalist>
                <div className="two-col">
                  <Field
                    label="Номер авто"
                    value={form.plateNumber}
                    onChange={updatePlateNumber}
                    placeholder="06KG 524 AVS"
                    list="plate-prefixes"
                    required
                  />
                  <datalist id="plate-prefixes">
                    {platePrefixes.map((prefix) => (
                      <option key={prefix} value={prefix} />
                    ))}
                  </datalist>
                  <SelectField label="Год выпуска" value={form.year} onChange={updateField("year")} required>
                    {years.map((year) => (
                      <option key={year} value={year}>
                        {year}
                      </option>
                    ))}
                  </SelectField>
                </div>
                <Field
                  label="VIN"
                  value={form.vin}
                  onChange={updateVin}
                  placeholder="KLYDC487DNC036233"
                  maxLength={17}
                  helper={`${form.vin.length}/17 символов`}
                  error={form.vin.length > 0 && form.vin.length !== 17 ? "VIN должен состоять из 17 символов" : ""}
                  required
                />
                <div className="form-actions two">
                  <button type="button" className="secondary-button" onClick={() => setStep(1)}>
                    Назад
                  </button>
                  <button type="button" className="primary-button" onClick={() => setStep(3)} disabled={!vehicleComplete}>
                    Продолжить
                  </button>
                </div>
              </div>
            ) : step === 3 ? (
              <div className="step-panel">
                <SectionTitle title="Подпись" />
                <div className="signature-box">
                  <canvas
                    ref={signatureCanvasRef}
                    width={720}
                    height={440}
                    onPointerDown={startSignature}
                    onPointerMove={drawSignature}
                    onPointerUp={endSignature}
                    onPointerCancel={endSignature}
                  />
                </div>
                <p className="signature-helper">Распишитесь пальцем внутри поля</p>
                <div className="form-actions two">
                  <button type="button" className="secondary-button" onClick={clearSignature}>
                    Очистить
                  </button>
                  <button type="button" className="primary-button" onClick={() => setStep(4)} disabled={!signatureData}>
                    Предпросмотр
                  </button>
                </div>
                <div className="form-actions">
                  <button type="button" className="secondary-button" onClick={() => setStep(2)}>
                    Назад
                  </button>
                </div>
              </div>
            ) : (
              <div className="step-panel">
                <SectionTitle title="Предпросмотр документа" />
                <p className="preview-note">Проверьте документ перед отправкой</p>
                <div className="form-actions two">
                  <button type="button" className="secondary-button" onClick={() => setStep(3)}>
                    Назад
                  </button>
                  <button type="button" className="primary-button" onClick={submitApplication} disabled={submitLoading}>
                    {submitLoading ? "Отправляем..." : "Отправить"}
                  </button>
                </div>
                {submitStatus ? <p className="scan-status">{submitStatus}</p> : null}
                {submitError ? <p className="field-error">{submitError}</p> : null}
              </div>
            )}
          </form>

          {step === 4 ? <ApplicationPreview form={form} signatureData={signatureData} /> : null}
        </div>
      </section>
    </main>
  );
}

function SectionTitle({ title }: { title: string }) {
  return (
    <div className="section-title">
      <h2>{title}</h2>
    </div>
  );
}

function Field({
  label,
  value,
  onChange,
  placeholder,
  required,
  type = "text",
  inputMode,
  list,
  maxLength,
  helper,
  error,
  autoComplete,
  onFocus,
  onBlur,
  ariaDescribedBy,
}: {
  label: string;
  value: string;
  onChange: (event: ChangeEvent<HTMLInputElement>) => void;
  placeholder: string;
  required?: boolean;
  type?: string;
  inputMode?: "text" | "search" | "none" | "tel" | "url" | "email" | "numeric" | "decimal";
  list?: string;
  maxLength?: number;
  helper?: string;
  error?: string;
  autoComplete?: string;
  onFocus?: () => void;
  onBlur?: () => void;
  ariaDescribedBy?: string;
}) {
  return (
    <label className="field">
      <span>
        {label}
        {required ? <b>*</b> : null}
      </span>
      <input
        value={value}
        onChange={onChange}
        placeholder={placeholder}
        type={type}
        inputMode={inputMode}
        list={list}
        maxLength={maxLength}
        autoComplete={autoComplete}
        onFocus={onFocus}
        onBlur={onBlur}
        aria-describedby={ariaDescribedBy}
      />
      {helper ? <small>{helper}</small> : null}
      {error ? <strong>{error}</strong> : null}
    </label>
  );
}

function SelectField({
  label,
  value,
  onChange,
  required,
  children,
}: {
  label: string;
  value: string;
  onChange: (event: ChangeEvent<HTMLSelectElement>) => void;
  required?: boolean;
  children: ReactNode;
}) {
  return (
    <label className="field">
      <span>
        {label}
        {required ? <b>*</b> : null}
      </span>
      <select value={value} onChange={onChange}>
        {children}
      </select>
    </label>
  );
}

function ApplicationPreview({ form, signatureData }: { form: FormState; signatureData: string }) {
  return (
    <aside className="preview-panel">
      <iframe className="document-frame" title="Предпросмотр заявки" srcDoc={buildApplicationDocument(form, signatureData)} />
    </aside>
  );
}

function isFieldComplete(key: keyof FormState, form: FormState) {
  if (key === "inn") return /^\d{14}$/.test(form.inn);
  if (key === "phone") return /^\+996\d{9}$/.test(form.phone.replace(/\s/g, ""));
  if (key === "vin") return /^[A-HJ-NPR-Z0-9]{17}$/.test(form.vin);
  return Boolean(form[key].trim());
}
