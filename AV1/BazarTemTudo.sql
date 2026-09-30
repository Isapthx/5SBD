CREATE DATABASE BazarTemTudo;
GO

USE BazarTemTudo
GO

CREATE TABLE Cliente (
    id INT IDENTITY(1, 1) PRIMARY KEY,
    cpf CHAR(11), -- identificador externo
    nome VARCHAR(100),
    email VARCHAR(254),
    telefone VARCHAR(15)
);
CREATE UNIQUE INDEX UQ_Cliente_CPF 
    ON Cliente(cpf) 
        WHERE cpf IS NOT NULL;
GO

CREATE TABLE Produto (
    id INT IDENTITY(1, 1) PRIMARY KEY,
    sku VARCHAR(50) UNIQUE NOT NULL, -- identificador externo
    nome VARCHAR(100) NOT NULL,
    upc VARCHAR(14)
);
GO

CREATE TABLE Pedido (
    id INT IDENTITY(1, 1) PRIMARY KEY,
    cliente_id INT,
    order_id VARCHAR(100) UNIQUE NOT NULL, -- identificador externo
    dat_compra DATETIME2 NOT NULL,
    data_pagamento DATETIME2,
    endereco_entrega VARCHAR(255),
    complemento_entrega VARCHAR(100),
    info_adicional_entrega VARCHAR(255),
    cidade_entrega VARCHAR(100),
    estado_entrega VARCHAR(100),
    codigo_postal VARCHAR(10),
    pais_entrega VARCHAR(60),
    servico_entrega VARCHAR(50),

    CONSTRAINT fk_cliente_pedido 
        FOREIGN KEY (cliente_id) REFERENCES Cliente(id)
);
GO

CREATE TABLE ItensPedido (
    id INT IDENTITY(1, 1) PRIMARY KEY,
    pedido_id INT NOT NULL,
    produto_id INT NOT NULL,
    order_item_id VARCHAR(100) NOT NULL, -- identificador externo
    quantidade INT NOT NULL,
    preco DECIMAL(10, 2),
    moeda CHAR(3),

    CONSTRAINT fk_pedido_itenspedido 
        FOREIGN KEY (pedido_id) REFERENCES Pedido(id),
    CONSTRAINT fk_produto_itenspedido 
        FOREIGN KEY (produto_id) REFERENCES Produto(id)
);
GO

CREATE TABLE MovimentacaoEstoque (
    id INT IDENTITY(1, 1) PRIMARY KEY, 
    pedido_id INT, 
    produto_id INT NOT NULL,
    quantidade INT NOT NULL, 
    tipo VARCHAR(7) NOT NULL, -- 'Entrada' ou 'Saída'
    data_movimento DATETIME2,

    CONSTRAINT fk_pedido_movimenta_estoque 
        FOREIGN KEY (pedido_id) REFERENCES Pedido(id),
    CONSTRAINT fk_produto_movimenta_estoque 
        FOREIGN KEY (produto_id) REFERENCES Produto(id)
);

CREATE TABLE Compras (
    id INT IDENTITY(1, 1) PRIMARY KEY, 
    pedido_id INT, 
    produto_id INT, 
    quantidade_necessaria INT, 
    status VARCHAR(20) DEFAULT 'PENDENTE',

    CONSTRAINT fk_pedido_compras 
        FOREIGN KEY (pedido_id) REFERENCES Pedido(id),
    CONSTRAINT fk_produto_compras 
        FOREIGN KEY (produto_id)  REFERENCES Produto(id)
);

CREATE TABLE PedidosTemp (
    id_carga INT IDENTITY(1, 1) PRIMARY KEY,
    order_id VARCHAR(100) NOT NULL,
    order_item_id VARCHAR(100) NOT NULL,
    purchase_date DATETIME2 NOT NULL,
    payments_date DATETIME2,
    buyer_email VARCHAR(254),
    buyer_name VARCHAR(100),
    cpf CHAR(11),
    buyer_phone_number VARCHAR(15),
    sku VARCHAR(50),
    upc VARCHAR(14),
    product_name VARCHAR(100),
    quantity_purchased INT,
    currency CHAR(3),
    item_price DECIMAL (10,2),
    ship_service_level VARCHAR(50),
    ship_address_1 VARCHAR(255),
    ship_address_2 VARCHAR(100),
    ship_address_3 VARCHAR(255),
    ship_city VARCHAR(100), 
    ship_state VARCHAR(100),
    ship_postal_code VARCHAR(10),
    ship_country VARCHAR(60)
);
GO

CREATE PROCEDURE importarPedidosTemp AS 
BEGIN
    BULK INSERT PedidosTemp FROM 'C:\Users\pires\Downloads\primeiraLinhaPedido.csv'
    WITH (
        FORMAT = 'CSV',
        FIRSTROW = 2,
        FIELDQUOTE = '"'
    );

END;
GO

CREATE PROCEDURE cadastrarClientes AS
BEGIN

    INSERT INTO Cliente (
        cpf,
        nome,
        email,
        telefone
    )
    SELECT DISTINCT 
        t.cpf,
        t.buyer_name,
        t.buyer_email,
        t.buyer_phone_number
    FROM PedidosTemp AS t 
        WHERE t.cpf IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 FROM Cliente AS c
            WHERE c.cpf = t.cpf
        );
END;
GO

CREATE PROCEDURE cadastrarProdutos AS
BEGIN

    INSERT INTO Produto (
        sku,
        nome,
        upc
    ) 
    SELECT DISTINCT
        t.sku,
        t.product_name,
        t.upc 
        FROM PedidosTemp AS t 
        WHERE t.sku IS NOT NULL
        AND NOT EXISTS (
            SELECT 1 FROM Produto AS p
            WHERE p.sku = T.sku
        );
END;
GO

CREATE PROCEDURE cadastrarPedidos
AS
BEGIN

    INSERT INTO Pedido (
        cliente_id,
        order_id,
        data_compra,
        data_pagamento,
        endereco_entrega,
        complemento_entrega,
        info_adicional_entrega,
        cidade_entrega,
        estado_entrega,
        codigo_postal,
        pais_entrega,
        servico_entrega
    )
    SELECT DISTINCT
        c.id,
        t.order_id,
        t.purchase_date,
        t.payments_date,
        t.ship_address_1,
        t.ship_address_2,
        t.ship_address_3,
        t.ship_city,
        t.ship_state,
        t.ship_postal_code,
        t.ship_country,
        t.ship_service_level
    FROM PedidosTemp AS t
    INNER JOIN Cliente AS c 
        ON c.cpf = t.cpf
    WHERE NOT EXISTS (
        SELECT 1
        FROM Pedido AS p
        WHERE p.order_id = t.order_id
    );
END;
GO

CREATE PROCEDURE cadastrarItensPedido
AS
BEGIN

    INSERT INTO ItensPedido (
        pedido_id,
        produto_id,
        order_item_id,
        quantidade,
        preco,
        moeda
    )
    SELECT
        p.id,
        pr.id,
        t.order_item_id,
        t.quantity_purchased,
        t.item_price,
        t.currency
    FROM PedidosTemp AS t
    INNER JOIN Pedido AS p
        ON p.order_id = t.order_id
    INNER JOIN Produto AS pr
        ON pr.sku = t.sku
    WHERE NOT EXISTS (
        SELECT 1
        FROM ItensPedido AS i
        WHERE i.order_item_id = t.order_item_id
    );
END;
GO

CREATE PROCEDURE processarEstoquePedidos
AS
BEGIN

    DECLARE
        @pedido_id INT,
        @produto_id INT,
        @quantidade INT,
        @estoque_atual INT;

    DECLARE cursor_pedidos CURSOR FOR

        SELECT
            p.id,
            pr.id,
            t.order_item_id,
            t.quantity_purchased
        FROM PedidosTemp AS t

        INNER JOIN Pedido AS p
            ON p.order_id = t.order_id

        INNER JOIN Produto AS pr
            ON pr.sku = t.sku

        WHERE NOT EXISTS (
            SELECT 1
            FROM MovimentacaoEstoque AS m
            WHERE m.pedido_id = p.id
              AND m.produto_id = pr.id
        );

    OPEN cursor_pedidos;

    FETCH NEXT FROM cursor_pedidos
    INTO @pedido_id, @produto_id, @order_item_id, @quantidade;

    WHILE @@FETCH_STATUS = 0
    BEGIN

        SELECT
            @estoque_atual =
                ISNULL(
                    SUM(
                        CASE
                            WHEN tipo = 'Entrada' THEN quantidade
                            WHEN tipo = 'Saída' THEN -quantidade
                            ELSE 0
                        END
                    ),
                    0
                )
        FROM MovimentacaoEstoque
        WHERE produto_id = @produto_id;


        IF @estoque_atual >= @quantidade
        BEGIN
            INSERT INTO MovimentacaoEstoque (
                pedido_id,
                produto_id,
                quantidade,
                tipo,
                data_movimento
            )
            VALUES (
                @pedido_id,
                @produto_id,
                @quantidade,
                'Saída',
                GETDATE()
            );
        END

        ELSE
        BEGIN
            INSERT INTO Compras (
                pedido_id,
                produto_id,
                quantidade_necessaria,
                status
            )
            VALUES (
                @pedido_id,
                @produto_id,
                @quantidade - @estoque_atual,
                'PENDENTE'
            );
        END;

        FETCH NEXT FROM cursor_pedidos
        INTO @pedido_id, @produto_id, @order_item_id, @quantidade;

    END;
    CLOSE cursor_pedidos;
    DEALLOCATE cursor_pedidos;
END;
GO