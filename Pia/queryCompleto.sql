
-- Crear base de datos
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'SistemaTareasEmpleados')
    DROP DATABASE SistemaTareasEmpleados;
GO

CREATE DATABASE SistemaTareasEmpleados;
GO

USE SistemaTareasEmpleados;
GO

-- Crear tablas
CREATE TABLE Empleados (
    id_empleado INT IDENTITY(1,1) PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL,
    correo VARCHAR(100) NOT NULL UNIQUE,
    area VARCHAR(50) NOT NULL
);
GO

CREATE TABLE Tareas (
    id_tarea INT IDENTITY(1,1) PRIMARY KEY,
    descripcion VARCHAR(200) NOT NULL,
    prioridad VARCHAR(10) DEFAULT 'Media' CHECK (prioridad IN ('Baja', 'Media', 'Alta')),
    duracion_estimada INT NULL
);
GO

CREATE TABLE Asignaciones (
    id_asignacion INT IDENTITY(1,1) PRIMARY KEY,
    id_empleado INT NOT NULL,
    id_tarea INT NOT NULL,
    fecha_asignacion DATETIME DEFAULT GETDATE(),
    fecha_limite DATE NOT NULL,
    estado VARCHAR(15) DEFAULT 'Pendiente' CHECK (estado IN ('Pendiente', 'Completada', 'Cancelada')),
    comentarios TEXT NULL,
    FOREIGN KEY (id_empleado) REFERENCES Empleados(id_empleado),
    FOREIGN KEY (id_tarea) REFERENCES Tareas(id_tarea)
);
GO

CREATE TABLE Bitacora_Tareas (
    id_bitacora INT IDENTITY(1,1) PRIMARY KEY,
    tabla VARCHAR(50),
    accion VARCHAR(50),
    descripcion TEXT,
    fecha DATETIME DEFAULT GETDATE()
);
GO

CREATE TABLE Alertas_Vencimiento (
    id_alerta INT IDENTITY(1,1) PRIMARY KEY,
    id_asignacion INT NOT NULL,
    mensaje VARCHAR(255),
    fecha DATETIME DEFAULT GETDATE(),
    FOREIGN KEY (id_asignacion) REFERENCES Asignaciones(id_asignacion)
);
GO

GO

GO

CREATE INDEX idx_estado_fecha ON Asignaciones(estado, fecha_limite);
GO

-- SP Registrar tarea
CREATE PROCEDURE SP_AsignarTarea
    @p_id_empleado INT,
    @p_id_tarea INT,
    @p_fecha_limite DATE,
    @p_comentarios TEXT
AS
BEGIN
    DECLARE @v_emp_exist INT;
    DECLARE @v_tarea_exist INT;
    
    SELECT @v_emp_exist = COUNT(*) FROM Empleados WHERE id_empleado = @p_id_empleado;
    SELECT @v_tarea_exist = COUNT(*) FROM Tareas WHERE id_tarea = @p_id_tarea;
    
    IF @v_emp_exist = 0
    BEGIN
        RAISERROR('Error: El empleado no existe.', 16, 1);
        RETURN;
    END
    
    IF @v_tarea_exist = 0
    BEGIN
        RAISERROR('Error: La tarea no existe.', 16, 1);
        RETURN;
    END
    
    IF @p_fecha_limite < CAST(GETDATE() AS DATE)
    BEGIN
        RAISERROR('Error: La fecha límite no puede ser anterior a hoy.', 16, 1);
        RETURN;
    END
    
    INSERT INTO Asignaciones (id_empleado, id_tarea, fecha_limite, comentarios, estado)
    VALUES (@p_id_empleado, @p_id_tarea, @p_fecha_limite, @p_comentarios, 'Pendiente');
END;
GO

-- SP Hacer tarea
CREATE PROCEDURE SP_CompletarTarea
    @p_id_asignacion INT
AS
BEGIN
    DECLARE @v_estado VARCHAR(20);
    
    SELECT @v_estado = estado FROM Asignaciones WHERE id_asignacion = @p_id_asignacion;
    
    IF @v_estado IS NULL
    BEGIN
        RAISERROR('Error: La asignación no existe.', 16, 1);
        RETURN;
    END
    
    IF @v_estado = 'Completada'
    BEGIN
        RAISERROR('Error: La tarea ya está completada.', 16, 1);
        RETURN;
    END
    
    UPDATE Asignaciones SET estado = 'Completada' WHERE id_asignacion = @p_id_asignacion;
END;
GO

-- SP Reporte de tareas
CREATE PROCEDURE SP_ReporteTareas
    @p_fecha_inicio DATE,
    @p_fecha_fin DATE
AS
BEGIN
    SELECT 
        a.id_asignacion,
        e.nombre AS empleado,
        t.descripcion AS tarea,
        a.fecha_asignacion,
        a.fecha_limite,
        a.estado,
        a.comentarios
    FROM Asignaciones a
    INNER JOIN Empleados e ON a.id_empleado = e.id_empleado
    INNER JOIN Tareas t ON a.id_tarea = t.id_tarea
    WHERE CAST(a.fecha_asignacion AS DATE) BETWEEN @p_fecha_inicio AND @p_fecha_fin
    ORDER BY a.fecha_asignacion DESC;
END;
GO

-- Trigger Alerta de tarea vencida (INSERT)
CREATE TRIGGER TR_Alerta_Vencimiento
ON Asignaciones
AFTER INSERT
AS
BEGIN
    INSERT INTO Alertas_Vencimiento (id_asignacion, mensaje)
    SELECT 
        i.id_asignacion,
        '⏰ La tarea "' + t.descripcion + '" está vencida desde el ' + CONVERT(VARCHAR, i.fecha_limite)
    FROM inserted i
    INNER JOIN Tareas t ON i.id_tarea = t.id_tarea
    WHERE i.fecha_limite < CAST(GETDATE() AS DATE) AND i.estado = 'Pendiente';
END;
GO

-- Trigger Bitácora cuando se completa una tarea
CREATE TRIGGER TR_Bitacora_Completadas
ON Asignaciones
AFTER UPDATE
AS
BEGIN
    INSERT INTO Bitacora_Tareas (tabla, accion, descripcion)
    SELECT 
        'Asignaciones',
        'COMPLETADA',
        'Empleado ID ' + CONVERT(VARCHAR, i.id_empleado) + 
        ' completó la tarea ID ' + CONVERT(VARCHAR, i.id_tarea) + 
        ' (Asignación ' + CONVERT(VARCHAR, i.id_asignacion) + ')'
    FROM inserted i
    INNER JOIN deleted d ON i.id_asignacion = d.id_asignacion
    WHERE i.estado = 'Completada' AND d.estado = 'Pendiente';
END;
GO

-- Datos demo
INSERT INTO Empleados (nombre, correo, area) VALUES
    ('Laura Méndez', 'laura.mendez@empresa.com', 'Ventas'),
    ('Roberto Soto', 'roberto.soto@empresa.com', 'Sistemas'),
    ('Karla Jiménez', 'karla.jimenez@empresa.com', 'Marketing');
GO

INSERT INTO Tareas (descripcion, prioridad, duracion_estimada) VALUES
    ('Preparar informe mensual', 'Alta', 4),
    ('Actualizar base de datos clientes', 'Media', 2),
    ('Diseñar campaña redes sociales', 'Alta', 6),
    ('Revisar backups', 'Baja', 1);
GO

INSERT INTO Asignaciones (id_empleado, id_tarea, fecha_limite, estado) VALUES
    (2, 2, DATEADD(DAY, 5, GETDATE()), 'Pendiente'),
    (1, 1, DATEADD(DAY, -2, GETDATE()), 'Pendiente'),
    (3, 3, DATEADD(DAY, 10, GETDATE()), 'Pendiente');


--Consultas de prueba
USE SistemaTareasEmpleados;
GO

SELECT * FROM Empleados;
SELECT * FROM Tareas;
SELECT * FROM Asignaciones;
SELECT * FROM Alertas_Vencimiento;
SELECT * FROM Bitacora_Tareas;
GO


EXEC SP_AsignarTarea 2, 4, DATEADD(DAY, 5, GETDATE()), 'Revisión semanal';
GO

SELECT * FROM Asignaciones ORDER BY id_asignacion DESC;
GO

EXEC SP_CompletarTarea 2;
GO

SELECT * FROM Asignaciones WHERE id_asignacion = 2;
SELECT * FROM Bitacora_Tareas;
GO

EXEC SP_AsignarTarea 2, 4, DATEADD(DAY, 5, GETDATE()), 'Revisión semanal';
GO
