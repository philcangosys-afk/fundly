-- فحص فقط (لا يغيّر شيئًا): لأي حساب حُفظت العقارات، وما صلاحيات جدولها.

-- 1) آخر العقارات/الأنشطة/المركبات وصاحب كل منها (البريد).
select a.title, a.category, u.email, a.user_id, a.created_at
from public.project_assets a
left join auth.users u on u.id = a.user_id
order by a.created_at desc
limit 30;

-- 2) سياسات الحماية على جدول العقارات.
select policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'project_assets';

-- 3) الحسابات الموجودة بأسمائها وأرقامها التعريفية.
select u.email, p.fnd_id, p.display_name, u.id
from auth.users u
left join public.profiles p on p.id = u.id
order by u.created_at;
