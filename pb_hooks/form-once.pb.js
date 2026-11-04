// form-once.pb.js — «один ответ с устройства» для анкет.
//
// Если у формы one_response_per_device = true, устройство (device_id)
// может отправить ответ только один раз. Повтор → 400 с понятным текстом.
//
// ВАЖНО: route-хуки и onRecord* — разные контексты в v0.28 JSVM.
// Здесь НЕТ известного бага «create-хук молча глушит запись»
// (он был на коллекции posts): e.next() вызывается всегда,
// ошибка бросается ДО записи. Проверено живьём.
//
// e.record на onRecordCreateRequest ещё не сохранён — читаем payload.
// device_id приходит в теле запроса (приложение шлёт его явно).

onRecordCreateRequest((e) => {
  const col = e.record.collection().name;
  if (col !== 'form_responses') {
    e.next();
    return;
  }

  const formId = e.record.get('form') || '';
  const deviceId = e.record.get('device_id') || '';

  if (formId && deviceId) {
    // включён ли режим «один ответ с устройства» на форме
    let once = false;
    try {
      const row = new DynamicModel({ flag: false });
      $app
        .db()
        .newQuery('SELECT one_response_per_device AS flag FROM forms WHERE id = {:id}')
        .bind({ id: formId })
        .one(row);
      once = row.flag === 1 || row.flag === true;
    } catch (err) {
      once = false;
    }

    if (once) {
      const counter = new DynamicModel({ n: 0 });
      $app
        .db()
        .newQuery('SELECT COUNT(*) AS n FROM form_responses WHERE form = {:f} AND device_id = {:d}')
        .bind({ f: formId, d: deviceId })
        .one(counter);
      if ((counter.n || 0) > 0) {
        throw new BadRequestError('Вы уже отвечали на эту анкету.');
      }
    }
  }

  e.next();
}, 'form_responses');
