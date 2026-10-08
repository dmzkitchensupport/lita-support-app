-- =============================================================================
-- LiTa Support -- Eliminación de cuenta (autoservicio), backend de TENANT.
-- Se aplica idéntica en: VK (lvugrhyknlftfgcngajc), CDJ (kjvmdfzacpygzozcvlby),
-- demo Fonda Raíz (vyrbajxcvqhvageyxblg). Vive en dmzkitchensupport/lita-support-app.
-- Prefijo rpc_eliminar_cuenta* / eliminacion_cuenta_* para no chocar con migraciones
-- de vitality-control / cdj-support.
--
-- Flujo (veredicto MAR CONDICIONADO, 8 oct 2026):
--   1. rpc_eliminar_cuenta_solicitar(correo, contraseña, canal) -- la llama el sitio
--      litasupport.com/api/eliminar-cuenta (web y app). Verifica identidad con la
--      contraseña real, bloquea al último admin/propietario, DESACTIVA el acceso de
--      inmediato y programa la ejecución a +10 días naturales (ventana para que el
--      empleador, vía Mario, marque datos con retención legal). Plazo LFPDPPP: respuesta
--      inmediata (folio) y ejecución dentro de los 15 días hábiles.
--   2. rpc_eliminar_cuenta_ejecutar_vencidas() -- pg_cron diario. Seudonimiza:
--      el colaborador conserva su id (actor_colaborador_id intacto) y su nombre/correo
--      pasan a "Colaborador #N · rol" en todos los registros operativos (NOM-251,
--      fiscales, turnos): se anonimizan, no se borran. Se BORRAN: credenciales,
--      historial de inicio de sesión, reportes técnicos con su correo, contadores de
--      seguridad y la firma de cierre SOLO si su ruta exacta está registrada (ver 2a).
--   3. Retención: update eliminacion_cuenta_solicitudes set estado='retenida',
--      retener_motivo='...' where folio='...';  (la ejecución automática la salta).
-- Sin correo directo al usuario ni al cliente: la alerta va solo a Mario (API web).
-- =============================================================================

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.eliminacion_cuenta_solicitudes (
  id               bigserial primary key,
  folio            text not null unique,
  colaborador_id   uuid,
  email            text,                     -- se borra (null) al ejecutar
  email_hash       text not null,            -- sha256(lower(correo)) para auditoría
  alias            text,
  rol              text,
  canal            text not null default 'web' check (canal in ('web','app','qa')),
  estado           text not null default 'pendiente'
                   check (estado in ('pendiente','retenida','ejecutada','cancelada')),
  retener_motivo   text,
  solicitada_at    timestamptz not null default now(),
  programada_para  timestamptz not null,
  ejecutada_at     timestamptz,
  detalle          jsonb not null default '{}'::jsonb
);

create table if not exists public.eliminacion_cuenta_auditoria (
  id          bigserial primary key,
  folio       text,
  email_hash  text,
  evento      text not null,
  detalle     jsonb not null default '{}'::jsonb,
  ts          timestamptz not null default now()
);
create index if not exists eliminacion_cuenta_auditoria_hash_ts
  on public.eliminacion_cuenta_auditoria (email_hash, ts);

-- Solo funciones SECURITY DEFINER tocan estas tablas: RLS activo, sin políticas.
alter table public.eliminacion_cuenta_solicitudes enable row level security;
alter table public.eliminacion_cuenta_auditoria  enable row level security;
revoke all on public.eliminacion_cuenta_solicitudes from anon, authenticated;
revoke all on public.eliminacion_cuenta_auditoria  from anon, authenticated;

-- La auditoría es de solo-inserción (registro inmutable a nivel de tabla).
create or replace function public._eliminacion_cuenta_auditoria_inmutable()
returns trigger language plpgsql as $$
begin
  raise exception 'eliminacion_cuenta_auditoria es de solo inserción';
end; $$;
drop trigger if exists eliminacion_cuenta_auditoria_inmutable on public.eliminacion_cuenta_auditoria;
create trigger eliminacion_cuenta_auditoria_inmutable
  before update or delete on public.eliminacion_cuenta_auditoria
  for each row execute function public._eliminacion_cuenta_auditoria_inmutable();

-- -----------------------------------------------------------------------------
-- 1. Solicitud (pública vía anon; la identidad se prueba con la contraseña real)
-- -----------------------------------------------------------------------------
create or replace function public.rpc_eliminar_cuenta_solicitar(
  p_email text, p_pass text, p_canal text default 'web')
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  u        colaboradores%rowtype;
  v_email  text := lower(btrim(coalesce(p_email, '')));
  v_hash   text := encode(digest(lower(btrim(coalesce(p_email, ''))), 'sha256'), 'hex');
  v_canal  text := case when p_canal in ('web','app','qa') then p_canal else 'web' end;
  v_sol    eliminacion_cuenta_solicitudes%rowtype;
  v_folio  text;
  v_otros  int;
begin
  -- Límite propio: 5 verificaciones fallidas por correo en 15 min.
  if (select count(*) from eliminacion_cuenta_auditoria
       where email_hash = v_hash and evento = 'verificacion_fallida'
         and ts > now() - interval '15 minutes') >= 5 then
    return json_build_object('ok', false, 'motivo', 'bloqueado');
  end if;

  select * into u from colaboradores where lower(email) = v_email and activo = true;
  if not found or u.pass_hash is null or crypt(coalesce(p_pass, ''), u.pass_hash) <> u.pass_hash then
    -- ¿Ya hay una solicitud pendiente de esta cuenta (que por eso quedó inactiva)?
    select * into v_sol from eliminacion_cuenta_solicitudes
     where email_hash = v_hash and estado in ('pendiente','retenida')
     order by id desc limit 1;
    if found then
      select * into u from colaboradores where id = v_sol.colaborador_id;
      if found and u.pass_hash is not null and crypt(coalesce(p_pass, ''), u.pass_hash) = u.pass_hash then
        return json_build_object('ok', true, 'folio', v_sol.folio, 'ya_existia', true,
                                 'programada_para', v_sol.programada_para);
      end if;
    end if;
    insert into eliminacion_cuenta_auditoria(email_hash, evento, detalle)
    values (v_hash, 'verificacion_fallida', json_build_object('canal', v_canal)::jsonb);
    return json_build_object('ok', false);
  end if;

  -- Condición MAR 5: nunca dejar al cliente sin un admin/propietario propio.
  if u.rol in ('admin','propietario') then
    select count(*) into v_otros from colaboradores
     where id <> u.id and activo = true and coalesce(hidden, false) = false
       and rol in ('admin','propietario')
       and split_part(lower(email), '@', 2) not in
           ('lita-support.internal','delamorazumaran.com','litasupport.com');
    if v_otros = 0 then
      insert into eliminacion_cuenta_auditoria(email_hash, evento, detalle)
      values (v_hash, 'rechazada_ultimo_admin', json_build_object('canal', v_canal)::jsonb);
      return json_build_object('ok', false, 'motivo', 'ultimo_admin');
    end if;
  end if;

  v_folio := 'EC-' || to_char(now() at time zone 'America/Mexico_City', 'YYYYMMDD') || '-'
             || upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 6));

  insert into eliminacion_cuenta_solicitudes
    (folio, colaborador_id, email, email_hash, rol, canal, programada_para)
  values
    (v_folio, u.id, v_email, v_hash, u.rol, v_canal, now() + interval '10 days')
  returning * into v_sol;

  -- Acceso desactivado de inmediato (rpc_login exige activo = true).
  update colaboradores set activo = false where id = u.id;

  insert into eliminacion_cuenta_auditoria(folio, email_hash, evento, detalle)
  values (v_folio, v_hash, 'solicitada_y_acceso_desactivado',
          json_build_object('canal', v_canal, 'rol', u.rol,
                            'programada_para', v_sol.programada_para)::jsonb);

  return json_build_object('ok', true, 'folio', v_folio,
                           'programada_para', v_sol.programada_para);
end; $$;

-- -----------------------------------------------------------------------------
-- 2. Ejecución de una solicitud (interna: sin grant a anon/authenticated)
-- -----------------------------------------------------------------------------
create or replace function public.rpc_eliminar_cuenta_ejecutar(p_folio text)
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare
  s        eliminacion_cuenta_solicitudes%rowtype;
  u        colaboradores%rowtype;
  v_full   text;
  v_email  text;
  v_alias  text;
  v_pat    text;
  r        record;
  n        bigint;
  v_tot    jsonb := '{}'::jsonb;
  v_firmas int := 0;
  v_borr   jsonb := '{}'::jsonb;
begin
  select * into s from eliminacion_cuenta_solicitudes where folio = p_folio for update;
  if not found then return json_build_object('ok', false, 'motivo', 'no_existe'); end if;
  if s.estado <> 'pendiente' then
    return json_build_object('ok', false, 'motivo', 'estado_' || s.estado);
  end if;

  select * into u from colaboradores where id = s.colaborador_id;
  v_email := lower(coalesce(s.email, u.email));
  v_full  := btrim(coalesce(u.nombre, '') || ' ' || coalesce(u.apellido, ''));
  v_alias := 'Colaborador #' || s.id || ' · ' || coalesce(nullif(u.rol, ''), 'colaborador');

  -- 2a. Firma de cierre (imagen). Corrección de la revisión de Cla, 8 oct: NUNCA por
  --     cercanía de tiempo (borraba firmas de otra persona que firmó en el mismo minuto).
  --     Solo se borra el objeto cuya ruta EXACTA quedó registrada a nombre de este correo
  --     en registro_actividad.detalle->>'path'. Al 8 oct, VK/CDJ guardan solo
  --     {contexto, dispositivo} y la ruta es fecha/firma-cierre_<ms>.jpg sin owner ni
  --     metadata: no hay liga exacta, así que hoy no se borra ninguna firma (se conservan
  --     como evidencia del cierre del empleador). Para borrarlas, los portales deben
  --     agregar `path` al detalle de sbInsertActividad('foto_subida', ...).
  if to_regclass('storage.objects') is not null and to_regclass('public.registro_actividad') is not null then
    perform set_config('storage.allow_delete_query', 'true', true);
    with f as (
      delete from storage.objects o
       where o.bucket_id = 'fotos-operativas'
         and o.name in (select ra.detalle->>'path' from registro_actividad ra
                         where lower(ra.colaborador_email) = v_email
                           and ra.accion = 'foto_subida'
                           and ra.detalle->>'contexto' = 'firma-cierre'
                           and ra.detalle ? 'path')
      returning 1)
    select count(*) into v_firmas from f;
    perform set_config('storage.allow_delete_query', 'false', true);
  end if;

  -- 2b. Borrados: historial de inicio de sesión, reportes técnicos, contadores.
  if to_regclass('public.registro_actividad') is not null then
    delete from registro_actividad where lower(colaborador_email) = v_email and accion = 'login';
    get diagnostics n = row_count; v_borr := v_borr || jsonb_build_object('registro_actividad_login', n);
  end if;
  if to_regclass('public.errores_cliente') is not null then
    delete from errores_cliente where lower(colaborador_email) = v_email;
    get diagnostics n = row_count; v_borr := v_borr || jsonb_build_object('errores_cliente', n);
  end if;
  if to_regclass('public.seguridad_intentos') is not null then
    delete from seguridad_intentos where clave = 'email:' || v_email;
    get diagnostics n = row_count; v_borr := v_borr || jsonb_build_object('seguridad_intentos', n);
  end if;

  -- 2c. Seudonimización en todo registro operativo (texto y jsonb).
  --     Nombre completo y correo -> alias. Se excluyen tablas de configuración/pago
  --     y los datos de comensales en encuestas.
  v_pat := '';
  if length(v_full) >= 5 then
    v_pat := regexp_replace(v_full, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g');
  end if;
  if v_email <> '' then
    v_pat := v_pat || case when v_pat = '' then '' else '|' end
             || regexp_replace(v_email, '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g');
  end if;

  if v_pat <> '' then
    for r in
      select c.table_name, c.column_name, c.data_type
        from information_schema.columns c
        join information_schema.tables t
          on t.table_schema = c.table_schema and t.table_name = c.table_name
       where c.table_schema = 'public' and t.table_type = 'BASE TABLE'
         and c.data_type in ('text', 'character varying', 'jsonb')
         and c.table_name not in ('colaboradores', 'eliminacion_cuenta_solicitudes',
              'eliminacion_cuenta_auditoria', 'pagos', 'vk_pagos', 'suscripciones', 'clientes',
              'app_config', 'vk_config', 'cj_config', 'seguridad_intentos', 'ia_usos',
              'diagnostico_ia_usos', 'modulo_horarios')
         and not (c.table_name = 'encuestas' and c.column_name in ('nombre', 'telefono', 'mail'))
    loop
      if r.data_type = 'jsonb' then
        execute format(
          'update public.%I set %I = regexp_replace(%I::text, $1, $2, ''gi'')::jsonb
            where %I::text ~* $1', r.table_name, r.column_name, r.column_name, r.column_name)
          using v_pat, v_alias;
      else
        execute format(
          'update public.%I set %I = regexp_replace(%I, $1, $2, ''gi'')
            where %I ~* $1', r.table_name, r.column_name, r.column_name, r.column_name)
          using v_pat, v_alias;
      end if;
      get diagnostics n = row_count;
      if n > 0 then
        v_tot := v_tot || jsonb_build_object(r.table_name || '.' || r.column_name, n);
      end if;
    end loop;
  end if;

  -- 2d. Cuenta: se conserva el id (trazabilidad NOM-251), se borran credenciales y PII.
  update colaboradores
     set email = 'eliminado+' || lower(s.folio) || '@lita-support.invalid',
         nombre = v_alias, apellido = '',
         pass_hash = null, pin_hash = null,
         activo = false, hidden = true
   where id = s.colaborador_id;

  update eliminacion_cuenta_solicitudes
     set estado = 'ejecutada', ejecutada_at = now(), email = null, alias = v_alias,
         detalle = jsonb_build_object('seudonimizados', v_tot, 'borrados', v_borr,
                                      'firmas_borradas', v_firmas)
   where id = s.id;

  insert into eliminacion_cuenta_auditoria(folio, email_hash, evento, detalle)
  values (s.folio, s.email_hash, 'ejecutada',
          jsonb_build_object('seudonimizados', v_tot, 'borrados', v_borr,
                             'firmas_borradas', v_firmas, 'alias', v_alias));

  return json_build_object('ok', true, 'folio', s.folio, 'alias', v_alias,
                           'seudonimizados', v_tot, 'borrados', v_borr,
                           'firmas_borradas', v_firmas);
end; $$;

-- -----------------------------------------------------------------------------
-- 3. Ejecución automática de solicitudes vencidas (pg_cron diario)
-- -----------------------------------------------------------------------------
create or replace function public.rpc_eliminar_cuenta_ejecutar_vencidas()
returns json
language plpgsql security definer
set search_path = public, extensions
as $$
declare r record; v_res jsonb := '[]'::jsonb;
begin
  for r in select folio from eliminacion_cuenta_solicitudes
            where estado = 'pendiente' and programada_para <= now() order by id
  loop
    begin
      v_res := v_res || jsonb_build_array(public.rpc_eliminar_cuenta_ejecutar(r.folio)::jsonb);
    exception when others then
      -- Un folio con error no detiene a los demás; queda registrado y sigue pendiente.
      insert into eliminacion_cuenta_auditoria(folio, evento, detalle)
      values (r.folio, 'error_ejecucion', jsonb_build_object('error', sqlerrm));
      v_res := v_res || jsonb_build_array(jsonb_build_object('ok', false, 'folio', r.folio, 'error', sqlerrm));
    end;
  end loop;
  return json_build_object('ok', true, 'ejecutadas', v_res);
end; $$;

-- -----------------------------------------------------------------------------
-- 4. Verificación de folio (anon, sin datos personales). La usa la API de
--    litasupport.com para confirmar que el folio existe antes de alertar a Mario.
-- -----------------------------------------------------------------------------
create or replace function public.rpc_eliminar_cuenta_verificar_folio(p_folio text)
returns json
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    (select json_build_object('existe', true, 'estado', estado, 'canal', canal,
                              'solicitada_at', solicitada_at, 'programada_para', programada_para)
       from eliminacion_cuenta_solicitudes where folio = p_folio),
    json_build_object('existe', false));
$$;
revoke all on function public.rpc_eliminar_cuenta_verificar_folio(text) from public;
grant execute on function public.rpc_eliminar_cuenta_verificar_folio(text) to anon, authenticated;

revoke all on function public.rpc_eliminar_cuenta_solicitar(text, text, text) from public;
revoke all on function public.rpc_eliminar_cuenta_ejecutar(text) from public;
revoke all on function public.rpc_eliminar_cuenta_ejecutar_vencidas() from public;
revoke all on function public.rpc_eliminar_cuenta_ejecutar(text) from anon, authenticated;
revoke all on function public.rpc_eliminar_cuenta_ejecutar_vencidas() from anon, authenticated;
grant execute on function public.rpc_eliminar_cuenta_solicitar(text, text, text) to anon, authenticated;

-- pg_cron: 14:15 UTC (08:15 CDMX) diario.
create extension if not exists pg_cron;
do $$
begin
  if exists (select 1 from cron.job where jobname = 'eliminar-cuenta-vencidas') then
    perform cron.unschedule('eliminar-cuenta-vencidas');
  end if;
  perform cron.schedule('eliminar-cuenta-vencidas', '15 14 * * *',
                        'select public.rpc_eliminar_cuenta_ejecutar_vencidas()');
end $$;
