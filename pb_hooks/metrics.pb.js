// metrics.pb.js — анонимные счётчики постов (просмотры/избранное).
//
// Проблема: update-правило posts — «только суперпользователь», поэтому
// приложение не может инкрементировать views_count/favorites_count само.
// Решение: два кастомных маршрута, инкремент выполняется на сервере.
//
//   POST /api/metrics/view/{postId}   — просмотр; заголовок X-Visitor-Id
//                                        (идентификатор устройства из SP)
//                                        дедуплицирует: 1 просмотр на посетителя.
//   POST /api/metrics/favorite        — { post_id, delta } где delta = 1 | -1;
//                                        счётчик не уходит ниже нуля.
//
// Особенность v0.28 (проверено на живом инстансе): тело route-хендлера
// компилируется отдельной программой и не видит ни область видимости файла,
// ни globalThis. Поэтому хендлеры полностью самодостаточны: DDL идемпотентен
// и выполняется на каждом запросе (для SQLite это дешёвый no-op), общее
// состояние не используется. Рейт-лимит не заведён: дедупликация уже режет
// накрутку просмотров, favorites — косметический счётчик с clamp на нуле.
//
// Дедупликация — служебная таблица metric_events (не коллекция, наружу
// не торчит); чистка старых строк — ночным cronAdd.
//
// Деплой: копия в репо (pb_hooks/metrics.pb.js), на сервере —
// /opt/mirea-pocketbase/pb_hooks/metrics.pb.js (хот-релоад на Linux).

// ---------- Ночная чистка событий старше 90 дней ----------
cronAdd("metricsCleanup", "0 4 * * *", () => {
  $app
    .db()
    .newQuery("DELETE FROM metric_events WHERE created_at < datetime('now', '-90 days')")
    .execute();
});

// ---------- POST /api/metrics/view/{postId} ----------
routerAdd("POST", "/api/metrics/view/{postId}", (e) => {
  const postId = e.request.pathValue("postId");
  const ip = e.realIP() || "unknown";

  // идемпотентная инициализация служебной таблицы
  $app
    .db()
    .newQuery(
      "CREATE TABLE IF NOT EXISTS metric_events (" +
        "id INTEGER PRIMARY KEY AUTOINCREMENT, " +
        "post_id TEXT NOT NULL, visitor TEXT NOT NULL, kind TEXT NOT NULL, " +
        "created_at DATETIME DEFAULT CURRENT_TIMESTAMP)"
    )
    .execute();
  $app
    .db()
    .newQuery(
      "CREATE UNIQUE INDEX IF NOT EXISTS metric_events_uniq ON metric_events (post_id, visitor, kind)"
    )
    .execute();

  // пост существует и опубликован?
  let status = "";
  try {
    const row = new DynamicModel({ status: "" });
    $app
      .db()
      .newQuery("SELECT status FROM posts WHERE id = {:id}")
      .bind({ id: postId })
      .one(row);
    status = row.status;
  } catch (err) {
    status = "";
  }
  if (status !== "published") return e.json(200, { counted: false });

  const visitor = (e.request.header.get("X-Visitor-Id") || ip).slice(0, 64);

  // дедупликация: 1 просмотр на посетителя (no rows -> .one() бросает ошибку)
  let seen = false;
  try {
    const row = new DynamicModel({ one: 0 });
    $app
      .db()
      .newQuery(
        "SELECT 1 as one FROM metric_events WHERE post_id = {:p} AND visitor = {:v} AND kind = 'view' LIMIT 1"
      )
      .bind({ p: postId, v: visitor })
      .one(row);
    seen = true;
  } catch (err) {
    seen = false;
  }
  if (seen) return e.json(200, { counted: false, reason: "already_counted" });

  $app
    .db()
    .newQuery("INSERT INTO metric_events (post_id, visitor, kind) VALUES ({:p}, {:v}, 'view')")
    .bind({ p: postId, v: visitor })
    .execute();
  $app
    .db()
    .newQuery("UPDATE posts SET views_count = views_count + 1 WHERE id = {:p}")
    .bind({ p: postId })
    .execute();

  return e.json(200, { counted: true });
});

// ---------- POST /api/metrics/favorite ----------
routerAdd("POST", "/api/metrics/favorite", (e) => {
  const body = new DynamicModel({ post_id: "", delta: 0 });
  e.bindBody(body);

  const postId = String(body.post_id || "").trim();
  const delta = Number(body.delta);
  if (!postId || (delta !== 1 && delta !== -1)) {
    throw new BadRequestError("post_id and delta (1 | -1) are required");
  }

  // пост существует и опубликован?
  let status = "";
  try {
    const row = new DynamicModel({ status: "" });
    $app
      .db()
      .newQuery("SELECT status FROM posts WHERE id = {:id}")
      .bind({ id: postId })
      .one(row);
    status = row.status;
  } catch (err) {
    status = "";
  }
  if (status !== "published") return e.json(200, { ok: false });

  $app
    .db()
    .newQuery("UPDATE posts SET favorites_count = max(0, favorites_count + {:d}) WHERE id = {:p}")
    .bind({ d: delta, p: postId })
    .execute();

  return e.json(200, { ok: true });
});
