// =====================================================================
//  MONGODB - CAPA ANALITICA Y REPORTES
//  Script 01: base de datos, colecciones e indices.
//  Ejecutar con:  mongosh -u admin -p ... --authenticationDatabase admin 01_crear_bd.js
//
//  Las colecciones guardan datos DESNORMALIZADOS que llegan desde
//  PostgreSQL por medio de mongo_fdw. Cada documento ya trae el nombre
//  del paciente, del medico, la sucursal, etc. para no tener que hacer
//  JOINs al momento de generar reportes.
// =====================================================================
db = db.getSiblingDB("reportes_medicos");

// --- resultados_estudios: un documento por estudio realizado ----------
//     Validacion basica: estos campos deben venir siempre.
db.createCollection("resultados_estudios", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["id_estudio", "paciente", "tipo", "fecha", "sucursal"],
      properties: {
        paciente: { bsonType: "string" },
        tipo:     { bsonType: "string" },
        sucursal: { bsonType: "string" }
      }
    }
  }
});

// --- resumen_paciente: un documento por paciente, se ACTUALIZA cada
//     vez que se registra un resultado nuevo en PostgreSQL ------------
db.createCollection("resumen_paciente");

// --- indicadores_mensuales: totales por mes, sucursal y tipo de estudio
db.createCollection("indicadores_mensuales");

// --- Indices para acelerar los reportes --------------------------------
db.resultados_estudios.createIndex({ id_estudio: 1 }, { unique: true });
db.resultados_estudios.createIndex({ medico: 1, tipo: 1 });
db.resultados_estudios.createIndex({ sucursal: 1, fecha: -1 });
db.resumen_paciente.createIndex({ id_paciente: 1 }, { unique: true });
db.indicadores_mensuales.createIndex({ mes: 1, sucursal: 1, tipo: 1 });

print("Base reportes_medicos creada. Colecciones:");
printjson(db.getCollectionNames());
