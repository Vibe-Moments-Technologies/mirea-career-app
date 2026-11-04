/**
 * Хук «Карьера МИРЭА»: мягкое удаление организаций.
 *
 * При удалении организации её посты НЕ удаляются (PocketBase по умолчанию
 * сносит их каскадом): отвязываем организацию, снимаем с публикации
 * (status=withdrawn, отдельная вкладка «Отозванные» в консоли).
 * Служебные организации (type=hidden/system) удалить нельзя.
 *
 * ВАЖНО (v0.28 JSVM): хендлеры — отдельные компилируемые программы без
 * file-scope; выборки — $app.findRecordsByFilter.
 *
 * #post_id генерируется консолью при создании поста (хук на create
 * в v0.28 ломал запись — молча 200 без сохранения).
 */
onRecordDeleteRequest((e) => {
  if (e.record.collection().name !== 'organizations') return;
  const type = e.record.get('type') || '';
  if (type === 'hidden' || type === 'system') {
    throw new BadRequestError('Служебную организацию удалить нельзя.');
  }
  const orgId = e.record.id;
  const orgName = e.record.get('name') || 'организация удалена';
  const posts = $app.findRecordsByFilter('posts', 'organization = "' + orgId + '"', '', 500, 0);
  for (let i = 0; i < posts.length; i++) {
    const post = posts[i];
    const author = post.get('author_name') || '';
    post.set('status', 'withdrawn');
    post.set('organization', '');
    post.set('author_name', author || orgName);
    $app.save(post);
  }
  // v0.28: без e.next() реальное удаление не происходит —
  // запрос отвечает 204 «успех», а запись остаётся в базе.
  e.next();
}, 'organizations');
