function Dock {
	parameter targetShip, safeDistance is minSafeDist().
	set targetShip to vessel(targetShip). //converting str to Vessel type object
	
	clearscreen.
	set ship:control:neutralize to true. //block user control inputs
	set ship:control:pilotmainthrottle to 0. //block user throttle inputs
	if (targetShip:typename <> "Vessel") {
		print "Error: the selected target is not a vessel.".
		return false.
	}
	else if (ship:body <> targetShip:body) {
		print "Error: the selected target must be in the same SOI.".
		return false.
	}
	
	//==========================================================//
	
	rcs on.
	sas off.
	ship:dockingports[0]:controlfrom.
	set tgtport to targetShip:dockingports[0].
	set elem to targetShip:elements:length.
	
	//DATA PRINTOUT
	print "Safety sphere radius: " + safeDistance + " m".
	print " ". print " ". print " ". print " ". //leaving two lines free for data printout
	print "Log:".
	local placeholder is "          ".
	when 1 then {
		local v_relative is ship:velocity:orbit - tgtport:ship:velocity:orbit.
		local dist is (tgtport:nodeposition - ship:controlpart:position):mag.
		
		print "Relative velocity  = " + round(v_relative:mag, 5) + placeholder at(0,2).
		print "Distance to target = " + round(dist, 2) + placeholder at(0,3).
		preserve.
	}
	
	if tgtport:ship:position:mag < safedistance {
		local facing0 is ship:facing.
		lock steering to facing0.
		// Отходим от цели по прямой со скоростью 2 м/с
		local lock v_relative to ship:velocity:orbit - tgtport:ship:velocity:orbit.
		local lock tgtpos to tgtport:ship:position.
		until tgtpos:mag > safedistance {
			local tgtvel is -tgtpos:normalized * 2.
			translatevec(tgtvel - v_relative).
			wait 0.
		}
		unlock v_relative.
		unlock tgtpos.
	}
	
	kill_relative_velocity(tgtport).
	lock steering to lookdirup(-tgtport:facing:forevector, tgtport:facing:topvector).
	approach(tgtport, safeDistance).
	dock_finalize(tgtport).
	return true.
	
	function minSafeDist { //intended to use only on docking init
		set box to vessel(targetShip):bounds.
		set absmin to box:relmin:mag.
		set absmax to box:relmax:mag.
		
		//max widespan of ship + 100 meters "keep-out sphere" radius
		return ceiling(max(absmin, absmax)+100).
	}
	
	function translatevec {
		parameter vector.
		local vec_copy is vector.
		//нормируем вектор, чтобы от него осталось только направление смещения
		if vector:sqrmagnitude > 1 {
			set vec_copy to vector:normalized.
		}
		local facing is ship:facing.
		local tf is vdot(vec_copy, facing:vector).
		local ts is vdot(vec_copy, facing:starvector).
		local tt is vdot(vec_copy, facing:topvector).
		set ship:control:translation to V(ts,tt,tf).
	}
	
	function kill_relative_velocity {
		parameter tgtport, threshold is 0.1.
		// threshold - относительная скорость, по достижении которой считаем цель неподвижной 
		// (по умолчанию ставим на 0.1 м/с)
		print "Killing relative velocity".
		local v_relative is ship:velocity:orbit - tgtport:ship:velocity:orbit.
		until v_relative:sqrmagnitude < threshold^2 {
			translatevec(-v_relative).
			wait 0.
			set v_relative to ship:velocity:orbit - tgtport:ship:velocity:orbit.
		}
		set ship:control:translation to V(0,0,0).
	}

	function v_safe {
		parameter dist.
		return sqrt(dist) / 2. // даёт 5 м/с на расстоянии 100 метров - вроде разумно
	}

	function move {
		parameter origin. // объект, относительно которого задаётся положение
		parameter pos. // где нужно оказаться относительно положения origin
		parameter vel is default_vel@. // с какой скоростью двигаться
		parameter tol is 0.5 * vel:call(). // в какой окрестности "засчитывается" попадание
		
		local lock v_wanted to vel:call() * (origin:position + pos):normalized.
		local lock v_relative to ship:velocity:orbit - origin:velocity:orbit.
		// "попали" тогда, когда ship:position - origin:position = pos
		// ship:position = pos + origin:position
		// а ship:position всегда равно V(0,0,0)
		until (origin:position + pos):mag < tol {	
			local lock v_wanted to vel:call() * (origin:position + pos):normalized.
			local lock v_relative to ship:velocity:orbit - origin:velocity:orbit.
			translatevec(v_wanted - v_relative).
		}
		unlock v_wanted.
		unlock v_relative.
		
		function default_vel {
			return v_safe(origin:position:mag-safeDistance). // +10).
		}
	}
	
	function approach {
		parameter tgtport, rsafe.
		local lock vec_i to tgtport:facing:vector.
		local lock vec_j to vxcl(vec_i, -tgtport:ship:position):normalized.
		
		// фаза I
		if vxcl(vec_i, -tgtport:ship:position):mag < rsafe {
			print "Going around the target".
			move(tgtport:ship, vxcl(vec_j, -tgtport:ship:position) + vec_j*rsafe).
			kill_relative_velocity(tgtport).
		}
		// фаза II
		if vdot(-tgtport:ship:position, vec_i) < rsafe {
			print "Getting in front of target".
			move(tgtport:ship, (vec_i + vec_j)*rsafe).
			kill_relative_velocity(tgtport).
		}
		// фаза III
		// выравниваемся уже не по центру масс корабля-цели, а по оси стыковочного узла
		print "Getting in front of target docking port".
		move(tgtport:ship, tgtport:position - tgtport:ship:position + vec_i*rsafe).
		kill_relative_velocity(tgtport).
		print "Ready for final approach".
		unlock vec_i.
		unlock vec_j.
	}
	
	function dock_finalize {
		parameter tgtport.
		
		kill_relative_velocity(tgtport).
		print "Starting final docking approach".
		local dist is tgtport:nodeposition:mag.
		
		// положение, в котором должен находиться центр 
		// масс активного аппарата относительно цетра масс 
		// цели, чтобы стыковочные узлы притянулись
		local newposition is tgtport:facing:vector * dist + tgtport:nodeposition - ship:controlpart:position - tgtport:ship:position.
		
		when 1 then {
			set vdraw to VECDRAW(tgtport:nodeposition, newposition, RGB(255,0,0), "newposition", 1, true, 0.2, true).
			preserve.
		}
		
		until ((tgtport:nodeposition - ship:controlpart:position):mag < tgtport:acquirerange*1.25) 
		OR (targetShip:elements:length > elem) {			
			move(tgtport:ship, newposition, dock_vel@, dist * 0.1).
			set newposition to tgtport:facing:vector * dist + tgtport:nodeposition - ship:controlpart:position - tgtport:ship:position.
			set dist to dist*0.9.
		}
		set ship:control:translation to V(0,0,0).
		unlock all.
		clearvecdraws().
		
		function dock_vel {
			return min(max(v_safe((tgtport:nodeposition - ship:controlpart:position):mag) / 5, 0.1), 2).
		}
	}
}