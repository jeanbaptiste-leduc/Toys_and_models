-- Queries_DataSolutions.sql
-- Ventes --

-- Taux de retour des clients (repeat customers) --

WITH recommande AS (
		SELECT 
			c.customerNumber
		FROM 
			customers c
		JOIN orders o 
			ON o.customerNumber = c.customerNumber
		JOIN orderdetails od 
			ON od.orderNUmber = o.orderNumber
		GROUP BY     
			c.customerNumber 
		HAVING COUNT(DISTINCT od.orderNumber) > 1
),
total_clients AS (
		SELECT COUNT(DISTINCT customerNumber) AS total
		FROM customers 
)

SELECT 
	(SELECT * FROM total_clients) AS 'Total Clients',
	COUNT(*) AS "Number of customers who repeat order",
    CONCAT(ROUND(100.0 * COUNT(*) / (SELECT total FROM total_clients),2), '%') AS "Percent repeat customers"
FROM recommande;

-- Taux d'evolution mensuel des ventes par catégorie --

SELECT 
	sub.productLine,
    sub.Month AS 'Month',
    sub.quantity AS Quantity,
    CONCAT(
    ROUND(
    (((sub.quantity -
    LAG(sub.quantity) OVER (
		partition by sub.productLine
		ORDER BY sub.Month
    )) 
    / LAG(sub.quantity) OVER (
		partition by sub.productLine
		ORDER BY sub.Month
    )) * 100)
    , 2)
    , ' %' ) AS 'Monthly Progress'
FROM (	SELECT 
		p.productLine,
		DATE_FORMAT(orderDate, '%Y-%m-01') AS MONTH,
		SUM(quantityOrdered) AS quantity
        
	FROM products p 
	LEFT JOIN orderdetails od ON od.productCode = p.productCode
	JOIN orders o ON o.orderNumber = od.orderNumber
	GROUP BY 
			p.productLine,
            DATE_FORMAT(orderDate, '%Y-%m-01'),
            YEAR(orderDate), 
            MONTH(orderDate)
           ) AS sub
ORDER BY sub.productLine, sub.Month
;

-- Panier moyen --  

WITH sum_by_order AS 
	(SELECT 
	od.orderNumber,
	SUM(quantityOrdered*priceEach) as Revenue
FROM 
	customers c
JOIN orders o 
	ON o.customerNumber = c.customerNumber
JOIN orderdetails od 
	ON od.orderNUmber = o.orderNumber
GROUP BY od.orderNumber
),
total_orders AS (
	SELECT 
		COUNT(DISTINCT orderNumber) AS total_orders
	FROM orderdetails
)
SELECT ROUND(AVG(Revenue),2) AS "Average basket",
	(SELECT total_orders from total_orders) AS 'total orders',
    (select sum(Revenue)) AS 'Revenue total'
FROM sum_by_order;

-- Chiffre d'affaires par mois et par région --

SELECT 
    off.officeCode AS "Office Id",
    off.city AS "Office city",
    CONCAT(MONTHNAME(cal.orderDate), ' ', YEAR(cal.orderDate)) AS "Date",
    COALESCE(SUM(od.priceEach * od.quantityOrdered), 0) AS "Revenue per Month",
    CASE
		WHEN 
        COALESCE(ROUND((COALESCE(SUM(od.priceEach * od.quantityOrdered), 0) -
    LAG(COALESCE(SUM(od.priceEach * od.quantityOrdered), 0))
        OVER (PARTITION BY off.officeCode ORDER BY YEAR(cal.orderDate), MONTH(cal.orderDate)))
	/ LAG(COALESCE(SUM(od.priceEach * od.quantityOrdered), 0)) 
        OVER (PARTITION BY off.officeCode ORDER BY YEAR(cal.orderDate), MONTH(cal.orderDate))
        * 100, 2),0) = 0
        THEN 'Not concerned'
	ELSE CONCAT(COALESCE(ROUND((COALESCE(SUM(od.priceEach * od.quantityOrdered), 0) -
    LAG(COALESCE(SUM(od.priceEach * od.quantityOrdered), 0))
        OVER (PARTITION BY off.officeCode ORDER BY YEAR(cal.orderDate), MONTH(cal.orderDate)))
	/ LAG(COALESCE(SUM(od.priceEach * od.quantityOrdered), 0))
        OVER (PARTITION BY off.officeCode ORDER BY YEAR(cal.orderDate), MONTH(cal.orderDate))
        * 100, 2),0), '%'
        )
        END
        AS 'Monthly progress'
FROM offices off
-- Pour ajouter les mois même si le chiffre d affaires =0 --
CROSS JOIN (
    SELECT DISTINCT 
        DATE_FORMAT(orderDate, '%Y-%m-01') AS orderDate
    FROM orders
) AS cal
LEFT JOIN employees e ON e.officeCode = off.officeCode
LEFT JOIN customers c ON c.salesRepEmployeeNumber = e.employeeNumber
LEFT JOIN orders o 
    ON o.customerNumber = c.customerNumber
    AND YEAR(o.orderDate) = YEAR(cal.orderDate)
    AND MONTH(o.orderDate) = MONTH(cal.orderDate)
LEFT JOIN orderdetails od ON od.orderNumber = o.orderNumber
GROUP BY 
    off.officeCode, 
    off.city,
    CONCAT(MONTHNAME(cal.orderDate), ' ', YEAR(cal.orderDate)),
    YEAR(cal.orderDate),
    MONTH(cal.orderDate)
ORDER BY 
    off.officeCode ASC, 
    YEAR(cal.orderDate) ASC,
    MONTH(cal.orderDate) ASC;

-- Calcule la marge brute totale pour chaque produit et chaque catégorie.

SELECT
    p.productLine AS 'Product line',
    p.productName AS 'Product Name',
    CONCAT(SUM(od.quantityOrdered * (od.priceEach - p.buyPrice)),' €') AS 'Gros margin'
    
FROM
    products p
JOIN
    orderdetails od ON p.productCode = od.productCode
GROUP BY
    p.productLine, p.productName
ORDER BY
    p.productLine, SUM(od.quantityOrdered * (od.priceEach - p.buyPrice)) DESC;
    
-- Ressources humaines --

-- Ratio commandes paiements par représentant commercial --

SELECT 
    rpe.salesRepEmployeeNumber AS 'Id employee',
    rpe.Name,
    SUM(payment.Payment) AS 'Total payments',
    SUM(rpe.Revenue_employee) AS 'Revenue per employee',
    SUM(rpe.Revenue_employee) - SUM(payment.Payment) AS 'Difference revenue',
    CONCAT(ROUND(((SUM(rpe.Revenue_employee) - SUM(payment.Payment))/SUM(rpe.Revenue_employee))*100, 2), "%") AS "Unpaid amounts per employee"
FROM (
    SELECT 
        c.salesRepEmployeeNumber,
        c.customerNumber,
        CONCAT(e.lastname, ' ', e.firstname) AS Name,
        SUM(od.priceEach * od.quantityOrdered) AS Revenue_employee
    FROM customers c
    LEFT JOIN orders o ON o.customerNumber = c.customerNumber
    LEFT JOIN orderdetails od ON o.orderNumber = od.orderNumber
    LEFT JOIN employees e ON e.employeeNumber = c.salesRepEmployeeNumber
    GROUP BY c.salesRepEmployeeNumber, c.customerNumber, e.lastname, e.firstname
) AS rpe
LEFT JOIN (
    SELECT 
        cu.salesRepEmployeeNumber,
        cu.customerNumber,
        SUM(p.amount) AS Payment
    FROM customers cu
    LEFT JOIN payments p ON p.customerNumber = cu.customerNumber
    GROUP BY cu.salesRepEmployeeNumber, cu.customerNumber
) AS payment 
ON payment.customerNumber = rpe.customerNumber
GROUP BY rpe.salesRepEmployeeNumber, rpe.Name
ORDER BY ((SUM(rpe.Revenue_employee) - SUM(payment.Payment))/SUM(rpe.Revenue_employee))*100 DESC;

-- Performances des représentants commerciaux

SELECT employeeNumber AS 'Id employee',
		CONCAT(lastname, ' ', firstname) AS 'Name',
		SUM(od.priceEach * od.quantityOrdered) AS 'Revenue per employee'
        
FROM customers c
LEFT JOIN employees e ON e.employeeNumber = c.salesRepEmployeeNumber
LEFT JOIN orders o ON o.customerNumber = c.customerNumber
LEFT JOIN orderdetails od ON o.orderNumber = od.orderNumber
GROUP by employeeNumber
order by SUM(od.priceEach * od.quantityOrdered) DESC;

-- Performance des représentants commerciaux avec commerciaux à 0€ --
SELECT employeeNumber AS 'Id employee',
		CONCAT(lastname, ' ', firstname) AS 'Name',
		COALESCE(SUM(od.priceEach * od.quantityOrdered), 0) AS 'Revenue per employee'
        
FROM customers c
RIGHT JOIN employees e ON e.employeeNumber = c.salesRepEmployeeNumber
LEFT JOIN orders o ON o.customerNumber = c.customerNumber
LEFT JOIN orderdetails od ON o.orderNumber = od.orderNumber
WHERE jobTitle = 'Sales Rep'
GROUP by employeeNumber
order by SUM(od.priceEach * od.quantityOrdered) DESC;

-- Performance des bureaux --

SELECT 
	e.officeCode AS 'Office Id',
    off.city,
	SUM(od.priceEach * od.quantityOrdered) AS 'Revenue per office'
FROM customers c
LEFT JOIN employees e ON e.employeeNumber = c.salesRepEmployeeNumber
LEFT JOIN orders o ON o.customerNumber = c.customerNumber
LEFT JOIN orderdetails od ON o.orderNumber = od.orderNumber
LEFT JOIN offices off ON off.officeCode = e.officeCode

GROUP BY e.officeCode, off.city

order BY SUM(od.priceEach * od.quantityOrdered) DESC;

-- Logistique --

-- Taux de commandes livrées en retard par rapport à la date prévue

SELECT 
		orderNumber,
        shippedDate,
        orderDate,
        comments
from orders
WHERE shippedDate > requiredDate
    
Order BY Datediff(shippedDate, orderDate) DESC;

-- Produis sous seuil critique 

SELECT *
FROM (SELECT 
    p.productCode AS Code_Produit,
    p.productName AS Nom_Produit,
    p.productVendor AS Fabricant,
    p.quantityInStock,
    MAX(od.quantityOrdered) AS Quantité_commandée_max
FROM 
    products p 
JOIN orderdetails od
    ON p.productCode = od.productCode
GROUP BY Code_Produit, Nom_Produit, Fabricant,p.quantityInStock
    ) AS seuil_critique
WHERE Quantité_commandée_max > quantityInStock;

-- Max quantité commandée

SELECT * FROM products;
SELECT * FROM offices;
SELECT 
	p.productCode AS Code_Produit,
	p.productName AS Nom_Produit,
    p.productVendor AS Fabricant,
    MAX(od.quantityOrdered) AS Quantité_commandée
FROM 
	products p 
JOIN orderdetails od
	ON p.productCode = od.productCode
GROUP BY Code_Produit, Nom_Produit, Fabricant
ORDER BY MAX(od.quantityOrdered) DESC;


-- Duree moyenne de traitement des commandes

SELECT CONCAT(ROUND(AVG(Datediff(shippedDate, orderDate)), 2) , ' days') AS 'Average days processing time'
from orders;

-- Commandes au dessus de la moyenne de livraison 

SELECT 
		orderNumber,
        shippedDate,
        orderDate,
        Datediff(shippedDate, orderDate) AS "Delay between order and delivery" 
from orders
WHERE Datediff(shippedDate, orderDate) > (
	SELECT 
	AVG(Datediff(shippedDate, orderDate)) AS avgdate
	from orders
	)
    
Order BY Datediff(shippedDate, orderDate) DESC;

-- Commandes annulées

SELECT 
		orderNumber,
        shippedDate,
        orderDate,
        comments
from orders
where status != "Shipped";

-- Finances

-- Taux de recouvrement des creances par client

SELECT 
    pay.customerNumber AS 'Id Number',
    pay.customerName AS Name,
    rev.number_orders AS 'Number orders',
    rev.revenue_per_customer AS 'Revenue per customer',
    pay.paid_invoice AS 'Paid invoice',
    rev.revenue_per_customer - pay.paid_invoice AS 'Amount unpaid',
    ROUND((rev.revenue_per_customer - pay.paid_invoice) / rev.revenue_per_customer * 100,2) AS 'Unpaid percentage'
    
FROM 
    (
        -- Clients générant le plus/moins de revenus --
        SELECT
            c.customerNumber,
            c.customerName,
            SUM(p.amount) AS paid_invoice
        FROM customers c
        JOIN payments p 
            ON c.customerNumber = p.customerNumber
        GROUP BY c.customerNumber, c.customerName
    ) AS pay
	JOIN 
    (
        -- Taux de recouvrement des créances par client --
        SELECT
            c.customerNumber,
            c.customerName,
            COUNT(DISTINCT o.orderNumber) AS number_orders,
            SUM(od.quantityOrdered * od.priceEach) AS revenue_per_customer
        FROM customers c
        JOIN orders o
            ON c.customerNumber = o.customerNumber
        JOIN orderdetails od
            ON o.orderNumber = od.orderNumber
        GROUP BY c.customerNumber, c.customerName
    ) AS rev
    ON rev.customerNumber = pay.customerNumber
ORDER BY rev.revenue_per_customer - pay.paid_invoice DESC;

-- Taux de paiement par délai

SELECT 
    c.customerNumber,
    c.customerName,
    rve.orderNumber,
    rve.revenue_per_order,
    p.paymentDate,
    DATEDIFF(p.paymentDate, rve.orderDate) AS "Payment delay"
FROM customers c
JOIN payments p ON p.customerNumber = c.customerNumber
JOIN (
    SELECT 
        o.orderNumber,
        o.customerNumber,
        o.orderDate,
        ROUND(SUM(od.quantityOrdered * od.priceEach),2) AS revenue_per_order
    FROM orderdetails od
    JOIN orders o ON o.orderNumber = od.orderNumber
    GROUP BY o.orderNumber, o.customerNumber
) AS rve ON c.customerNumber = rve.customerNumber
		AND rve.revenue_per_order = p.amount

order BY customerNumber;

-- produits les plus moins vendus par catégorie
SELECT 
	p.productline,
    od.productCode,
    p.productname,
SUM(od.quantityOrdered) AS total_quantity
FROM orderdetails od
JOIN products p ON od.productCode = p.productCode
GROUP BY p.productline, p.productcode, p.productname
ORDER BY p.productline, total_quantity DESC;

-- Montant moyen des paiements
SELECT ROUND(AVG(amount)) AS 'Montant moyen des paiements'
FROM payments;

-- Clients générant le plus de revenus + taux de recouvrement par client
SELECT rev.customerNumber As "Customer ID",
		rev.customerName AS "Customer Name",
        rev.total_revenue As "Total Revenue",
        pay.total_payment AS "Total paid",
        rev.total_revenue - pay.total_payment AS "Unpaid amount",
        CONCAT(ROUND(((pay.total_payment / rev.total_revenue) * 100), 2), '%') AS "Recovery rate"

FROM		(SELECT
			c.customerNumber,
			c.customerName,
			SUM(p.amount) AS total_payment
		FROM customers c
		JOIN payments p 
			ON c.customerNumber = p.customerNumber
		GROUP BY c.customerNumber, c.customerName) AS pay
        
JOIN 
(SELECT
    c.customerNumber,
    c.customerName,
    SUM(od.quantityOrdered * od.priceEach) AS total_revenue
FROM customers c
Left JOIN orders ord 
	On c.customerNumber = ord.customerNumber
LEFT JOIN orderdetails od
	ON od.orderNumber = ord.orderNumber
GROUP BY c.customerNumber, c.customerName) AS rev

ON rev.customerNumber = pay.customerNumber
ORder BY rev.total_revenue - pay.total_payment DESC;

-- délai moyen de paiement
select CONCAT(ROUND(AVG(pd.payment_delay),2 ), ' jours') AS 'Payment delay'
FROM (SELECT 
    c.customerNumber,
    c.customerName,
    rve.orderNumber,
    rve.revenue_per_order,
    p.paymentDate,
    DATEDIFF(p.paymentDate, rve.orderDate) AS payment_delay
FROM customers c
JOIN payments p ON p.customerNumber = c.customerNumber
JOIN (
    SELECT 
        o.orderNumber,
        o.customerNumber,
        o.orderDate,
        ROUND(SUM(od.quantityOrdered * od.priceEach),2) AS revenue_per_order
    FROM orderdetails od
    JOIN orders o ON o.orderNumber = od.orderNumber
    GROUP BY o.orderNumber, o.customerNumber
) AS rve ON c.customerNumber = rve.customerNumber
		AND rve.revenue_per_order = p.amount) AS pd;
        
-- croissance des ventes par trimestre
WITH QuarterlySales AS (
    SELECT
        YEAR(o.orderDate) AS sales_year,
        QUARTER(o.orderDate) AS sales_quarter,
        SUM(od.quantityOrdered * od.priceEach) AS total_sales
    FROM
        orders o
    JOIN
        orderdetails od ON o.orderNumber = od.orderNumber
    GROUP BY
        sales_year,
        sales_quarter)
SELECT
    sales_year,
    sales_quarter,
    total_sales,
    LAG(total_sales, 1, 0) OVER (ORDER BY sales_year, sales_quarter) AS previous_quarter_sales,
    CASE
        WHEN LAG(total_sales, 1, 0) OVER (ORDER BY sales_year, sales_quarter) = 0 THEN 0
        ELSE (total_sales - LAG(total_sales, 1, 0) OVER (ORDER BY sales_year, sales_quarter)) * 100.0 / LAG(total_sales, 1, 0) OVER (ORDER BY sales_year, sales_quarter)
    END AS growth_rate_pct
FROM
    QuarterlySales
ORDER BY
    sales_year, sales_quarter;
    
-- Clients en dessous de la moyenne des paiements
SELECT p.customerNumber AS CustomerId,
	c.customerName As 'Name',
    ROUND(AVG(amount)) AS 'Average payment'
FROM customers c
JOIN payments p ON p.customerNumber = c.customerNUmber
WHERE amount < (SELECT ROUND(AVG(amount)) AS montant_moyen_paiements
		FROM payments
)
GROUP BY p.customerNumber,
		c.customerName