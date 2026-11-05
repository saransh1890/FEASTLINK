USE feastlink;

-- CTE: summarize each shelter's completed donation impact
WITH shelter_impact AS (
 SELECT s.shelter_id,s.shelter_name,
        COALESCE(SUM(h.meals_served),0) AS meals_served,
        COALESCE(SUM(h.beneficiary_count),0) AS beneficiaries
 FROM shelter_homes s
 LEFT JOIN food_requests r ON r.shelter_id=s.shelter_id
 LEFT JOIN food_allocations a ON a.request_id=r.request_id
 LEFT JOIN donation_history h ON h.allocation_id=a.allocation_id
 GROUP BY s.shelter_id,s.shelter_name
)
SELECT * FROM shelter_impact ORDER BY meals_served DESC;

-- Recursive CTE: generate a 7-day reporting calendar, including days with zero donations
WITH RECURSIVE days(day) AS (
 SELECT CURDATE() - INTERVAL 6 DAY
 UNION ALL
 SELECT day + INTERVAL 1 DAY FROM days WHERE day < CURDATE()
)
SELECT days.day, COALESCE(SUM(h.meals_served),0) AS meals_served
FROM days
LEFT JOIN donation_history h ON DATE(h.completion_date)=days.day
GROUP BY days.day ORDER BY days.day;

-- Correlated subquery + function: show available meals per active food listing
SELECT food_id,food_name,estimated_meals,meals_remaining(food_id) AS remaining_meals
FROM surplus_food WHERE available_until>NOW();

-- Multi-table JOIN: full trace from event through request, allocation and delivery
SELECT e.event_name,sf.food_name,sh.shelter_name,r.requested_meals,
       r.status AS request_status,fa.allocated_meals,d.delivery_status
FROM events e
JOIN surplus_food sf ON sf.event_id=e.event_id
JOIN food_requests r ON r.food_id=sf.food_id
JOIN shelter_homes sh ON sh.shelter_id=r.shelter_id
LEFT JOIN food_allocations fa ON fa.request_id=r.request_id
LEFT JOIN delivery d ON d.allocation_id=fa.allocation_id
ORDER BY r.request_date DESC;

-- Window function: rank shelters by total meals served
SELECT shelter_name,meals_served,
       DENSE_RANK() OVER(ORDER BY meals_served DESC) AS impact_rank
FROM (
 SELECT sh.shelter_name,COALESCE(SUM(dh.meals_served),0) AS meals_served
 FROM shelter_homes sh
 LEFT JOIN food_requests fr ON fr.shelter_id=sh.shelter_id
 LEFT JOIN food_allocations fa ON fa.request_id=fr.request_id
 LEFT JOIN donation_history dh ON dh.allocation_id=fa.allocation_id
 GROUP BY sh.shelter_id,sh.shelter_name
) ranked;
