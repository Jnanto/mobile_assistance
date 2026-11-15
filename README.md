# 🌿 SelvaCheck

> **Sistema institucional de registro y verificación presencial de asistencia**  
> Universidad de la Amazonia — Florencia, Caquetá, Colombia.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Spark%20Plan-FFCA28?logo=firebase&logoColor=black)](https://firebase.google.com)
[![Platform](https://img.shields.io/badge/Plataforma-Android-3DDC84?logo=android&logoColor=white)](https://developer.android.com)
[![Licencia](https://img.shields.io/badge/Licencia-Educativa%20%2F%20UDLA-green)](#)

---

## 📋 Descripción del Proyecto

**SelvaCheck** es una aplicación móvil desarrollada en **Flutter** para optimizar y asegurar el registro de asistencia académica presencial en la Universidad de la Amazonia. La aplicación implementa un esquema de validación multicapa para garantizar la presencia física del estudiante y prevenir fraudes o suplantaciones:

1. **Código QR Dinámico:** Se proyecta desde el dispositivo del docente y rota periódicamente cada 20 segundos con tokens de corta duración validados directamente mediante reglas de seguridad de Firestore.
2. **Geocerca GPS:** Valida la distancia entre el estudiante y el docente en el momento de la clase, con protección ante aplicaciones de ubicación simulada (*mock locations*).
3. **Verificación de Red WiFi (BSSID):** Valida la conexión o cercanía a los puntos de acceso institucional registrados por el docente al abrir la sesión.
4. **Vinculación a Dispositivo Único:** El estudiante queda enlazado a un único dispositivo físico, impidiendo que una persona registre asistencias ajenas desde su teléfono.

La solución está diseñada y optimizada para operar sobre el **plan gratuito Spark de Firebase**, prescindiendo de Cloud Functions y servicios de pago, garantizando costo cero de infraestructura.

---

## 🔑 Credenciales de Acceso de Prueba (Administrador / Docente)

Para evaluar y administrar la plataforma con todos los privilegios docentes (creación de cursos, inicio de sesiones en vivo, proyección de QR, revisión de marcas, importación y exportación de reportes), utilice la siguiente cuenta precargada:

| Campo | Valor |
| :--- | :--- |
| **Rol** | **Administrador / Docente** |
| **Correo institucional** | `hec.rodriguez@udla.edu.co` |
| **Contraseña** | `12345678` |

> [!NOTE]
> Las cuentas con rol de **Docente** tienen acceso completo a la gestión de cursos, visualización de métricas en tiempo real, corrección manual justificada de asistencias y exportación de reportes en PDF y Excel.

---

## 🛠️ Requisitos Previos

Antes de instalar y ejecutar el proyecto, asegúrese de contar con las siguientes herramientas en su entorno:

- **Git:** Control de versiones ([git-scm.com](https://git-scm.com/)).
- **Flutter SDK:** Versión estable 3.24 o superior (Dart 3.5+) ([flutter.dev/docs/get-started/install](https://docs.flutter.dev/get-started/install)).
- **Java Development Kit (JDK):** Versión 17 (requerida para compilar el proyecto Android con Gradle).
- **Android Studio** o **VS Code**: Con las extensiones de Flutter y Dart instaladas.
- **Android SDK & Command-line Tools:** Android API 34+ con `coreLibraryDesugaring` y soporte de arquitectura compatible.
- **Dispositivo físico Android** (Recomendado) con Android 8.0 (API 26) o superior, con permisos de Cámara y Ubicación habilitados; o un emulador con Google Play Services activado.

---

## 🚀 Instrucciones de Instalación y Ejecución

### 1. Clonar el repositorio

```bash
git clone https://github.com/hector132000/mobile_assistance.git
cd mobile_assistance
```

### 2. Descargar las dependencias del proyecto

Ejecute en la raíz del proyecto para descargar todos los paquetes de Flutter y dependencias:

```bash
flutter pub get
```

### 3. Configuración de Firebase

Los archivos de configuración del proyecto Firebase (`selvacheck-1d238`) ya vienen incluidos en el repositorio:
- `lib/firebase_options.dart` (Configuración de Firebase para Flutter)
- `android/app/google-services.json` (Configuración nativa de Google Services para Android)
- `firebase.json` y `firestore.rules` (Definición y reglas de seguridad de Firestore)

> [!TIP]
> No es obligatorio ejecutar `flutterfire configure` a menos que desee asociar el proyecto a un Firebase propio. Si cuenta con Firebase CLI instalado y desea sincronizar las reglas de seguridad en su consola, ejecute:
> ```bash
> firebase deploy --only firestore:rules
> ```

### 4. Conectar un dispositivo o emulador

Verifique que su dispositivo sea detectado correctamente:

```bash
flutter devices
```

### 5. Ejecutar la aplicación

Para iniciar la aplicación en modo desarrollo / depuración:

```bash
flutter run
```

Si dispone de varios dispositivos o emuladores conectados:

```bash
flutter run -d <DEVICE_ID>
```

### 6. Compilar el ejecutable APK (Opcional)

Para generar el archivo APK instalable para Android en modo release:

```bash
flutter build apk --release
```

El APK resultante se ubicará en:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 🧪 Pruebas Automatizadas y Calidad de Código

El repositorio cuenta con una suite completa de pruebas unitarias y de widgets implementadas con `fake_cloud_firestore` y simuladores de hardware:

- **Ejecutar análisis estático:**
  ```bash
  flutter analyze
  ```
- **Ejecutar suite de pruebas unitarias y de integración:**
  ```bash
  flutter test
  ```

---

## 🏗️ Arquitectura y Stack Tecnológico

El proyecto sigue una arquitectura modular y orientada a capas:

```
lib/
├── core/                  # Configuración global, temas visuales M3, utilidades y rutas
│   ├── config/            # AppConfig: tolerancias, tiempos de rotación QR, límites
│   ├── router/            # AppRouter y GoRouter con redirección por estado de sesión
│   └── theme/             # Tokens de diseño, estilos y animaciones (AppMotion)
├── data/                  # Capa de datos y persistencia
│   ├── models/            # Modelos de usuario, cursos, sesiones y asistencias
│   ├── repositories/      # Acceso a colecciones de Cloud Firestore
│   └── services/          # Integraciones: GPS, WiFi, exportación PDF/Excel, lector XLS
├── features/              # Módulos funcionales de la aplicación
│   ├── auth/              # Inicio de sesión, registro, vinculación y recuperación
│   ├── profile/           # Perfil de usuario, bloqueo biométrico y foto de perfil
│   ├── student/           # Vista de cursos, escáner QR y comprobantes
│   └── teacher/           # Creación de cursos, clase en vivo, reportes y métricas
└── shared/                # Componentes visuales y widgets reutilizables
```

### Tecnologías principales

- **Gestión de Estado:** `Provider` (`MultiProvider`, `ChangeNotifierProvider`).
- **Navegación:** `GoRouter` reactivo sincronizado con el ciclo de vida de autenticación.
- **Persistencia en la Nube:** Google Cloud Firestore (Plan Spark) con persistencia local habilitada.
- **Autenticación:** Firebase Authentication restringido al dominio institucional `@udla.edu.co`.
- **Lector de Listas Académicas:** Motor de lectura propio en Dart para formatos binarios `.xls` (BIFF8 / OLE2) de la Universidad de la Amazonia, además de `.xlsx` y `.csv`.
- **Reportes:** Motor de exportación local en PDF (`pdf`) y hojas de cálculo Excel (`excel`).
- **Seguridad local:** Desbloqueo biométrico con `local_auth` y notificaciones locales con `flutter_local_notifications`.

---

## 📱 Funcionalidades Principales

### 👨‍🏫 Módulo Docente / Administrador
- **Gestión de Asignaturas:** Configuración de 1 a 2 encuentros semanales con día, bloque, salón y radio de tolerancia en metros.
- **Importación Masiva de Estudiantes:** Carga directa del archivo oficial `.xls` o `.xlsx` generado por el sistema académico institucional.
- **Clase en Vivo:** Transmisión de QR dinámico (rotación cada 20 segundos) con captura automática de coordenadas GPS y BSSID de la red del salón.
- **Control y Auditoría:** Marcado manual de asistencias, aprobación o rechazo de registros en estado *"Por revisar"*, y justificaciones con historial.
- **Reportes y Analítica:** Gráficas de asistencia, detección de estudiantes en riesgo de pérdida (>20% de inasistencia) y exportación a PDF y Excel.

### 👨‍🎓 Módulo Estudiante
- **Registro Controlado:** Vinculación directa con el pre-registro realizado por el docente.
- **Enlace a Dispositivo Único:** Protección anti-fraude vinculando el teléfono del estudiante a su identificador de hardware local.
- **Marcado de Asistencia en Tres Pasos:** Verificación automática de ubicación GPS, confirmación de red WiFi institucional y escaneo rápido del QR dinámico.
- **Historial y Comprobantes:** Consulta detallada de asistencias por curso, porcentaje acumulado, avisos de inasistencia y descarga de constancia digital.

---

## ⚖️ Políticas y Reglas de Negocio

- **Límite de Inasistencia:** 20% del total de clases programadas. Al superar el 15% se activa una alerta preventiva visual.
- **Tolerancia Horaria:**
  - `0 a 10 minutos`: **Presente** (configurable por el docente a 5, 10, 15 o 20 min).
  - `+5 minutos posteriores`: **Tarde** (las llegadas tarde no suman como inasistencia para reprobación).
  - `Transcurrida la tolerancia`: **Ausente**.
- **Sesión por Inactividad:** Cierre de sesión automático tras 10 minutos de inactividad para proteger la cuenta del usuario en dispositivos compartidos.

---

## 👥 Créditos y Contacto

- **Institución:** Universidad de la Amazonia.
- **Programa:** Ingeniería de Sistemas / Programación Móvil.
- **Soporte / Contacto:** `hec.rodriguez@udla.edu.co`.
