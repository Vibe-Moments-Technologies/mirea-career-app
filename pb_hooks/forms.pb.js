// forms.pb.js — количество ответов на анкету (анонимно).
//
// form_responses закрыты для чтения (create-only для студентов), поэтому
// приложение не может посчитать ответы само. Здесь — единственный маршрут:
//
//   GET /api/forms/responses-count/{formId} → { count: N }
//
// Возвращает ТОЛЬКО число: кто и что отвечал — не раскрывается.
// Форма должна существовать и быть активной (is_active), иначе count: 0 —
// не отдаём даже факт существования неактивной анкеты.
//
// Особенность v0.28: тело route-хендлера компилируется отдельной
// программой (см. metrics.pb.js) — хендлер самодостаточен.
//
// Деплой: копия в репо (pb_hooks/forms.pb.js), на сервере —
// /opt/mirea-pocketbase/pb_hooks/forms.pb.js (хот-релоад на Linux).

// ---------- GET /api/forms/responses-count/{formId} ----------
routerAdd("GET", "/api/forms/responses-count/{formId}", (e) => {
  const formId = e.request.pathValue("formId");
  if (!formId) throw new BadRequestError("formId is required");

  // форма активна? неактивная или удалённая — ноль без деталей.
  let active = false;
  try {
    const row = new DynamicModel({ is_active: false });
    $app
      .db()
      .newQuery("SELECT is_active FROM forms WHERE id = {:id}")
      .bind({ id: formId })
      .one(row);
    active = row.is_active === 1 || row.is_active === true;
  } catch (err) {
    active = false;
  }
  if (!active) return e.json(200, { count: 0 });

  const counter = new DynamicModel({ n: 0 });
  $app
    .db()
    .newQuery("SELECT COUNT(*) as n FROM form_responses WHERE form = {:id}")
    .bind({ id: formId })
    .one(counter);

  return e.json(200, { count: counter.n || 0 });
});
