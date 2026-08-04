WITH
	screenshots AS (
		SELECT
			image_id,
			date,
			time,
			pid,
			objects
		FROM `[REDACTED]`
	),
	pid_map AS (
		SELECT
			participant_id,
			pid
		FROM `[REDACTED]`
		WHERE participant_id IS NOT NULL
			AND pid IS NOT NULL
	),
	period_index AS (
		SELECT
			participant_id,
			period_id,
			COALESCE(
				SAFE_CAST(period_start AS TIMESTAMP),
				TIMESTAMP(SAFE_CAST(period_start AS DATETIME))
			) AS period_start_ts,
			COALESCE(
				SAFE_CAST(period_end AS TIMESTAMP),
				TIMESTAMP(SAFE_CAST(period_end AS DATETIME))
			) AS period_end_ts
		FROM `[REDACTED]`
		WHERE participant_id IS NOT NULL
			AND period_id IS NOT NULL
	),
	missing_intervals_raw AS (
		SELECT
			participant_id,
			start_time_utc_cleaned,
			end_time_utc_cleaned
		FROM `[REDACTED]`
		WHERE participant_id IS NOT NULL
	),
	missing_intervals AS (
		SELECT
			participant_id,
			COALESCE(
				SAFE_CAST(r.start_time_utc_cleaned AS TIMESTAMP),
				TIMESTAMP(SAFE_CAST(r.start_time_utc_cleaned AS DATETIME))
			) AS missing_start_ts,
			COALESCE(
				SAFE_CAST(r.end_time_utc_cleaned AS TIMESTAMP),
				TIMESTAMP(SAFE_CAST(r.end_time_utc_cleaned AS DATETIME))
			) AS missing_end_ts
		FROM missing_intervals_raw r
		WHERE r.start_time_utc_cleaned IS NOT NULL
			AND r.end_time_utc_cleaned IS NOT NULL
			AND COALESCE(
				SAFE_CAST(r.end_time_utc_cleaned AS TIMESTAMP),
				TIMESTAMP(SAFE_CAST(r.end_time_utc_cleaned AS DATETIME))
			) > COALESCE(
				SAFE_CAST(r.start_time_utc_cleaned AS TIMESTAMP),
				TIMESTAMP(SAFE_CAST(r.start_time_utc_cleaned AS DATETIME))
			)
	),

	-- Expand person objects once, then compute exact overlap-aware union area per screenshot.
	base_screenshots AS (
		SELECT
			s.image_id,
			m.participant_id,
			TIMESTAMP(DATETIME(s.date, s.time)) AS screenshot_ts,
			s.objects
		FROM screenshots s
		JOIN pid_map m
			ON s.pid = m.pid
	),
	person_boxes AS (
		SELECT
			b.image_id,
			b.participant_id,
			b.screenshot_ts,
			GREATEST(0.0, LEAST(640.0, LEAST(o.location[OFFSET(0)], o.location[OFFSET(2)]))) AS x1,
			GREATEST(0.0, LEAST(640.0, GREATEST(o.location[OFFSET(0)], o.location[OFFSET(2)]))) AS x2,
			GREATEST(0.0, LEAST(480.0, LEAST(o.location[OFFSET(1)], o.location[OFFSET(3)]))) AS y1,
			GREATEST(0.0, LEAST(480.0, GREATEST(o.location[OFFSET(1)], o.location[OFFSET(3)]))) AS y2
		FROM base_screenshots b
		CROSS JOIN UNNEST(b.objects) o
		WHERE o.content = 'person'
			AND o.prob >= 0.7
			AND ARRAY_LENGTH(o.location) >= 4
	),
	valid_boxes AS (
		SELECT
			image_id,
			participant_id,
			screenshot_ts,
			x1,
			x2,
			y1,
			y2
		FROM person_boxes
		WHERE x2 > x1
			AND y2 > y1
	),
	x_edges AS (
		SELECT image_id, participant_id, screenshot_ts, x1 AS x FROM valid_boxes
		UNION DISTINCT
		SELECT image_id, participant_id, screenshot_ts, x2 AS x FROM valid_boxes
	),
	x_strips AS (
		SELECT
			image_id,
			participant_id,
			screenshot_ts,
			ROW_NUMBER() OVER (
				PARTITION BY image_id, participant_id, screenshot_ts
				ORDER BY x
			) AS strip_id,
			x AS x_left,
			LEAD(x) OVER (
				PARTITION BY image_id, participant_id, screenshot_ts
				ORDER BY x
			) AS x_right
		FROM x_edges
	),
	active_intervals AS (
		SELECT
			xs.image_id,
			xs.participant_id,
			xs.screenshot_ts,
			xs.strip_id,
			xs.x_left,
			xs.x_right,
			v.y1,
			v.y2
		FROM x_strips xs
		JOIN valid_boxes v
			ON v.image_id = xs.image_id
		 AND v.participant_id = xs.participant_id
		 AND v.screenshot_ts = xs.screenshot_ts
		 AND v.x1 < xs.x_right
		 AND v.x2 > xs.x_left
		WHERE xs.x_right IS NOT NULL
			AND xs.x_right > xs.x_left
	),
	intervals_with_prev AS (
		SELECT
			image_id,
			participant_id,
			screenshot_ts,
			strip_id,
			x_left,
			x_right,
			y1,
			y2,
			MAX(y2) OVER (
				PARTITION BY image_id, participant_id, screenshot_ts, strip_id
				ORDER BY y1, y2
				ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING
			) AS prev_max_y2
		FROM active_intervals
	),
	union_area_by_screenshot AS (
		SELECT
			image_id,
			participant_id,
			screenshot_ts,
			COALESCE(
				SUM(
					(x_right - x_left) * GREATEST(0.0, y2 - GREATEST(y1, COALESCE(prev_max_y2, y1)))
				),
				0.0
			) AS union_area_px
		FROM intervals_with_prev
		GROUP BY image_id, participant_id, screenshot_ts
	),
	has_person_by_screenshot AS (
		SELECT
			image_id,
			participant_id,
			screenshot_ts,
			TRUE AS has_person
		FROM person_boxes
		GROUP BY image_id, participant_id, screenshot_ts
	),
	screenshot_features AS (
		SELECT
			b.image_id,
			b.participant_id,
			b.screenshot_ts,
			COALESCE(h.has_person, FALSE) AS has_person,
			SAFE_DIVIDE(100.0 * COALESCE(u.union_area_px, 0.0), 640.0 * 480.0) AS person_area_pct
		FROM base_screenshots b
		LEFT JOIN has_person_by_screenshot h
			ON h.image_id = b.image_id
		 AND h.participant_id = b.participant_id
		 AND h.screenshot_ts = b.screenshot_ts
		LEFT JOIN union_area_by_screenshot u
			ON u.image_id = b.image_id
		 AND u.participant_id = b.participant_id
		 AND u.screenshot_ts = b.screenshot_ts
	),

	-- Keep only screenshots that fall inside a valid study period.
	scoped AS (
		SELECT
			sf.image_id,
			sf.participant_id,
			p.period_id,
			sf.screenshot_ts,
			sf.has_person,
			sf.person_area_pct
		FROM screenshot_features sf
		JOIN period_index p
			ON sf.participant_id = p.participant_id
		 AND p.period_start_ts IS NOT NULL
		 AND p.period_end_ts IS NOT NULL
		 AND sf.screenshot_ts BETWEEN p.period_start_ts AND p.period_end_ts
	),

	-- 1) Proportion of screenshots containing at least one person.
	period_person_proportion AS (
		SELECT
			participant_id,
			period_id,
			COUNT(*) AS n_screenshots,
			COUNTIF(has_person) AS n_person_screenshots,
			SAFE_DIVIDE(COUNTIF(has_person), COUNT(*)) AS prop_screens_with_person
		FROM scoped
		GROUP BY participant_id, period_id
	),

	-- Build contiguous person bouts by ordering screenshots and splitting at non-person rows.
	ordered AS (
		SELECT
			participant_id,
			period_id,
			image_id,
			screenshot_ts,
			has_person,
			person_area_pct,
			SUM(CASE WHEN has_person THEN 0 ELSE 1 END)
				OVER (
					PARTITION BY participant_id, period_id
					ORDER BY screenshot_ts, image_id
					ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
				) AS bout_group
		FROM scoped
	),
	person_rows AS (
		SELECT
			participant_id,
			period_id,
			image_id,
			screenshot_ts,
			person_area_pct,
			bout_group
		FROM ordered
		WHERE has_person
	),
	bouts AS (
		SELECT
			participant_id,
			period_id,
			bout_group,
			MIN(screenshot_ts) AS bout_start_ts,
			MAX(screenshot_ts) AS bout_end_ts,
			COUNT(*) AS n_screenshots_in_bout,
			TIMESTAMP_DIFF(MAX(screenshot_ts), MIN(screenshot_ts), SECOND) AS bout_duration_seconds
		FROM person_rows
		GROUP BY participant_id, period_id, bout_group
	),
	bouts_qc AS (
		SELECT
			b.participant_id,
			b.period_id,
			b.bout_group,
			b.bout_start_ts,
			b.bout_end_ts,
			b.n_screenshots_in_bout,
			b.bout_duration_seconds,
			LAG(b.bout_end_ts) OVER (
				PARTITION BY b.participant_id, b.period_id
				ORDER BY b.bout_start_ts, b.bout_group
			) AS prev_bout_end_ts,
			EXISTS (
				SELECT 1
				FROM missing_intervals mi
				WHERE mi.participant_id = b.participant_id
					AND mi.missing_start_ts < b.bout_end_ts
					AND mi.missing_end_ts > b.bout_start_ts
			) AS bout_overlaps_missing
		FROM bouts b
	),
	bouts_with_gaps AS (
		SELECT
			participant_id,
			period_id,
			bout_group,
			bout_start_ts,
			bout_end_ts,
			n_screenshots_in_bout,
			bout_duration_seconds,
			bout_overlaps_missing,
			CASE
				WHEN prev_bout_end_ts IS NULL THEN NULL
				WHEN EXISTS (
					SELECT 1
					FROM missing_intervals mi
					WHERE mi.participant_id = b.participant_id
						AND mi.missing_start_ts < b.bout_start_ts
						AND mi.missing_end_ts > b.prev_bout_end_ts
				) THEN NULL
				ELSE TIMESTAMP_DIFF(bout_start_ts, prev_bout_end_ts, SECOND)
			END AS seconds_since_previous_bout,
			CASE
				WHEN prev_bout_end_ts IS NULL THEN FALSE
				ELSE EXISTS (
					SELECT 1
					FROM missing_intervals mi
					WHERE mi.participant_id = b.participant_id
						AND mi.missing_start_ts < b.bout_start_ts
						AND mi.missing_end_ts > b.prev_bout_end_ts
				)
			END AS gap_overlaps_missing
		FROM bouts_qc b
	),

	-- 3) Bout duration and between-bout interval summaries by participant-period.
	bout_timing_summary AS (
		SELECT
			participant_id,
			period_id,
			COUNT(*) AS n_bouts,
			COUNTIF(bout_overlaps_missing) AS n_bouts_overlapping_missing,
			AVG(bout_duration_seconds) AS mean_bout_duration_seconds,
			STDDEV_SAMP(bout_duration_seconds) AS sd_bout_duration_seconds,
			AVG(seconds_since_previous_bout) AS mean_time_between_bouts_seconds,
			STDDEV_SAMP(seconds_since_previous_bout) AS sd_time_between_bouts_seconds,
			COUNTIF(gap_overlaps_missing) AS n_between_bout_gaps_ignored_missing
		FROM bouts_with_gaps
		GROUP BY participant_id, period_id
	),

	-- 4) Per-bout person-area summaries.
	bout_area_stats AS (
		SELECT
			participant_id,
			period_id,
			bout_group,
			AVG(person_area_pct) AS bout_mean_person_area_pct,
			COALESCE(STDDEV_SAMP(person_area_pct), 0.0) AS bout_sd_person_area_pct
		FROM person_rows
		GROUP BY participant_id, period_id, bout_group
	),
	area_percentiles AS (
		SELECT
			participant_id,
			period_id,
			PERCENTILE_CONT(bout_mean_person_area_pct, 0.5)
				OVER (PARTITION BY participant_id, period_id) AS median_bout_mean_person_area_pct,
			PERCENTILE_CONT(bout_sd_person_area_pct, 0.5)
				OVER (PARTITION BY participant_id, period_id) AS median_bout_sd_person_area_pct
		FROM bout_area_stats
	),
	area_summary AS (
		SELECT
			participant_id,
			period_id,
			MAX(median_bout_mean_person_area_pct) AS median_bout_mean_person_area_pct,
			MAX(median_bout_sd_person_area_pct) AS median_bout_sd_person_area_pct
		FROM area_percentiles
		GROUP BY participant_id, period_id
	)

SELECT
	p.participant_id,
	p.period_id,
	p.n_screenshots,
	p.n_person_screenshots,
	p.prop_screens_with_person,
	t.n_bouts,
	t.n_bouts_overlapping_missing,
	t.mean_bout_duration_seconds,
	t.sd_bout_duration_seconds,
	t.mean_time_between_bouts_seconds,
	t.sd_time_between_bouts_seconds,
	t.n_between_bout_gaps_ignored_missing,
	a.median_bout_mean_person_area_pct,
	a.median_bout_sd_person_area_pct
FROM period_person_proportion p
LEFT JOIN bout_timing_summary t
	USING (participant_id, period_id)
LEFT JOIN area_summary a
	USING (participant_id, period_id)
ORDER BY participant_id, period_id;