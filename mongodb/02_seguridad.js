// =====================================================================
//  MONGODB - Script 02: roles y usuarios
//  Autenticacion: SCRAM-SHA-256 (usuario + contrasena).
//
//  usr_fdw_pg_mongo -> interno: lo usa PostgreSQL (mongo_fdw) para
//                      escribir. Solo puede find/insert/update/remove
//                      en las 3 colecciones del proyecto. No puede
//                      borrar colecciones ni crear usuarios.
//  usr_api_web      -> externo: solo lectura de toda la base de reportes.
//  usr_api_mobile   -> externo: solo lectura de 2 colecciones resumidas.
// =====================================================================
db = db.getSiblingDB("reportes_medicos");

// ---------- Rol personalizado para el FDW (permisos minimos) ----------
db.createRole({
  role: "rol_fdw_escritura",
  privileges: [
    { resource: { db: "reportes_medicos", collection: "resultados_estudios" },
      actions: ["find", "insert", "update", "remove"] },
    { resource: { db: "reportes_medicos", collection: "resumen_paciente" },
      actions: ["find", "insert", "update", "remove"] },
    { resource: { db: "reportes_medicos", collection: "indicadores_mensuales" },
      actions: ["find", "insert", "update", "remove"] }
  ],
  roles: []
});

// ---------- Rol personalizado para la app movil ------------------------
db.createRole({
  role: "rol_movil_lectura",
  privileges: [
    { resource: { db: "reportes_medicos", collection: "resumen_paciente" },
      actions: ["find"] },
    { resource: { db: "reportes_medicos", collection: "indicadores_mensuales" },
      actions: ["find"] }
  ],
  roles: []
});

// ---------- Usuarios ----------------------------------------------------
db.createUser({
  user: "usr_fdw_pg_mongo",
  pwd: "Fdw_Mongo2026",
  roles: [{ role: "rol_fdw_escritura", db: "reportes_medicos" }],
  mechanisms: ["SCRAM-SHA-256"]
});

db.createUser({
  user: "usr_api_web",
  pwd: "Api_Web2026",
  roles: [{ role: "read", db: "reportes_medicos" }],
  mechanisms: ["SCRAM-SHA-256"]
});

db.createUser({
  user: "usr_api_mobile",
  pwd: "Api_Mobile2026",
  roles: [{ role: "rol_movil_lectura", db: "reportes_medicos" }],
  mechanisms: ["SCRAM-SHA-256"]
});

print("Usuarios de reportes_medicos:");
db.getUsers().users.forEach(u =>
  print(" - " + u.user + " -> " + u.roles.map(r => r.role).join(", ")));
