using Plots
using MeshCat
using GeometryTypes
using CoordinateTransformations
using FileIO
using MeshIO
using LinearAlgebra
import TrajectoryOptimization: AbstractSolver, solve_aula!

function cable_transform(y,z)
    v1 = [0,0,1]
    v2 = y[1:3,1] - z[1:3,1]
    normalize!(v2)
    ax = cross(v1,v2)
    ang = acos(v1'v2)
    R = AngleAxis(ang,ax...)
    compose(Translation(z),LinearMap(R))
end

function plot_cylinder(vis,c1,c2,radius,mat,name="")
    geom = Cylinder(Point3f0(c1),Point3f0(c2),convert(Float32,radius))
    setobject!(vis["cyl"][name],geom,mat)
end

function addcylinders!(vis,cylinders,height=1.5)
    for (i,cyl) in enumerate(cylinders)
        plot_cylinder(vis,[cyl[1],cyl[2],0],[cyl[1],cyl[2],height],cyl[3],MeshPhongMaterial(color=RGBA(1, 0, 0, 0.5)),"cyl_$i")
    end
end

function visualize_quadrotor_lift_system(vis, probs, scenario=:doorway, n_slack=3)
    prob_load = probs[1]
    prob_lift = probs[2:end]
    r_lift = .275
    r_load = .2
    ceiling = 2.1

    obs = scenario == :doorway

    if scenario == :doorway
        _cyl = door_obstacles()
        addcylinders!(vis,_cyl,ceiling)
    elseif scenario == :slot
        y_bnd = 3
        slot_horiz, slot_vert = slot_obstacles()
        mat = MeshPhongMaterial(color=RGBA(1,0,0, 0.5))
        for (i,cyl) in enumerate(slot_horiz)
            i == 3 ? y_bnd = 2 : y_bnd = 3
            c1 = [cyl[1], y_bnd, cyl[2]]
            c2 = [cyl[1],-y_bnd, cyl[2]]
            plot_cylinder(vis, c1, c2, cyl[3], mat, "hcyl$i")
        end
        addcylinders!(vis, slot_vert, ceiling+0.2)
        addcylinders!(vis, slot_vert[1:2], ceiling)
    end


    num_lift = length(prob_lift)
    d = [norm(prob_lift[i].x0[1:n_slack] - prob_load.x0[1:n_slack]) for i = 1:num_lift]

    # camera angle
    # settransform!(vis["/Cameras/default"], compose(Translation(5., -3, 3.),LinearMap(RotX(pi/25)*RotZ(-pi/2))))

    # load in quad mesh
    traj_folder = joinpath(dirname(pathof(TrajectoryOptimization)),"..")
    urdf_folder = joinpath(traj_folder, "dynamics","urdf")
    obj = joinpath(urdf_folder, "quadrotor_base.obj")

    quad_scaling = 0.085
    robot_obj = FileIO.load(obj)
    robot_obj.vertices .= robot_obj.vertices .* quad_scaling

    col_cylinder = Cylinder(Point3f0([0,0,0]), Point3f0([0,0,3.]), Float32(0.275))

    # intialize system
    for i = 1:num_lift
        # setobject!(vis["lift$i"]["sphere"],HyperSphere(Point3f0(0), convert(Float32,r_lift)) ,MeshPhongMaterial(color=RGBA(0, 0, 0, 0.25)))
        setobject!(vis["lift$i"]["robot"],robot_obj,MeshPhongMaterial(color=RGBA(0, 0, 0, 1.0)))
        # setobject!(vis["collision$i"], col_cylinder, MeshPhongMaterial(color=RGBA(0, 1, 0, 0.5)))

        cable = Cylinder(Point3f0(0,0,0),Point3f0(0,0,d[i]),convert(Float32,0.01))
        setobject!(vis["cable"]["$i"],cable,MeshPhongMaterial(color=RGBA(1, 0, 0, 1.0)))
    end
    setobject!(vis["load"],HyperSphere(Point3f0(0), convert(Float32,r_load)) ,MeshPhongMaterial(color=RGBA(0, 1, 0, 1.0)))


    anim = MeshCat.Animation(convert(Int,floor(1/prob_lift[1].dt)))
    for k = 1:prob_lift[1].N
        MeshCat.atframe(anim,vis,k) do frame
            # cables
            x_load = prob_load.X[k][1:n_slack]
            for i = 1:num_lift
                x_lift = prob_lift[i].X[k][1:n_slack]
                settransform!(frame["cable"]["$i"], cable_transform(x_lift,x_load))
                settransform!(frame["lift$i"], compose(Translation(x_lift...),LinearMap(Quat(prob_lift[i].X[k][4:7]...))))
                # settransform!(frame["collision$i"], Translation(x_lift...))

            end
            settransform!(frame["load"], Translation(x_load...))
        end
    end
    MeshCat.setanimation!(vis,anim)
end

function visualize_batch(vis,prob,scenario=:doorway,num_lift=3)

    # camera angle
    # settransform!(vis["/Cameras/default"], compose(Translation(5., -3, 3.),LinearMap(RotX(pi/25)*RotZ(-pi/2))))

    obs = scenario == :doorway
    if obs
        _cyl = door_obstacles()
        addcylinders!(vis, _cyl, 2.1)
    end
    x0 = prob.x0
    d = norm(x0[1:3] - x0[num_lift*13 .+ (1:3)])

    if scenario == :slot
        slot_min = 0.5
        slot_max = 1.5
        block1 = HyperRectangle(4.5, -2, 0, 1, 4, slot_min)
        block2 = HyperRectangle(4.5, -2, slot_max, 1, 4, 1)
        setobject!(vis["slot"]["block1"], block1, MeshPhongMaterial(color=RGBA(0,1,0,0.0)))
        setobject!(vis["slot"]["block2"], block2, MeshPhongMaterial(color=RGBA(0,1,0,0.0)))
    end

    # intialize system
    traj_folder = joinpath(dirname(pathof(TrajectoryOptimization)),"..")
    urdf_folder = joinpath(traj_folder, "dynamics","urdf")
    obj = joinpath(urdf_folder, "quadrotor_base.obj")

    quad_scaling = 0.085
    robot_obj = FileIO.load(obj)
    robot_obj.vertices .= robot_obj.vertices .* quad_scaling
    for i = 1:num_lift
        setobject!(vis["lift$i"],robot_obj,MeshPhongMaterial(color=RGBA(0, 0, 0, 1.0)))
        cable = Cylinder(Point3f0(0,0,0),Point3f0(0,0,d),convert(Float32,0.01))
        setobject!(vis["cable"]["$i"],cable,MeshPhongMaterial(color=RGBA(1, 0, 0, 1.0)))
    end
    setobject!(vis["load"],HyperSphere(Point3f0(0), convert(Float32,0.2)) ,MeshPhongMaterial(color=RGBA(0, 1, 0, 1.0)))

    anim = MeshCat.Animation(convert(Int,floor(1.0/prob.dt)))
    for k = 1:prob.N
        MeshCat.atframe(anim,vis,k) do frame
            # cables
            x_load = prob.X[k][num_lift*13 .+ (1:3)]
            for i = 1:num_lift
                x_lift = prob.X[k][(i-1)*13 .+ (1:3)]
                q_lift = prob.X[k][((i-1)*13 + 3) .+ (1:4)]
                settransform!(frame["cable"]["$i"], cable_transform(x_lift,x_load))
                settransform!(frame["lift$i"], compose(Translation(x_lift...),LinearMap(Quat(q_lift...))))
            end
            settransform!(frame["load"], Translation(x_load...))
        end
    end
    MeshCat.setanimation!(vis,anim)
end
