;; this is a collection of utility functions and macros
;; for euslisp coordination system interface and
;; ros coordination system interface

;; load c-binding library
(load-library "eustf.so" '("eustf"))

;; include ros messages packages
(ros::roseus-add-msgs "roslib")
(ros::roseus-add-msgs "std_msgs")
(ros::roseus-add-msgs "geometry_msgs")

;; convert unit....
;; position convert : WG use [m], JSK use eus [mm]
;; quaternion convert: WG use axis-angle quaternion, JSK use angle-axis quaternion

;; eus->tf
(defun ros::pos->tf-point (pos)
  (instance geometry_msgs::point :init
            :x (* 0.001 (elt pos 0)) :y (* 0.001 (elt pos 1)) :z (* 0.001 (elt pos 2))))
(defun ros::pos->tf-translation (pos)
  (instance geometry_msgs::vector3 :init
            :x (* 0.001 (elt pos 0)) :y (* 0.001 (elt pos 1)) :z (* 0.001 (elt pos 2))))

(defun ros::rot->tf-quaternion (rot)
  (let* ((q (matrix2quaternion rot))
         (qx (elt q 1)) (qy (elt q 2)) (qz (elt q 3)) (qw (elt q 0)))
    (instance geometry_msgs::quaternion :init
              :x qx :y qy :z qz :w qw)))

(defun ros::coords->tf-pose (coords)
  (instance geometry_msgs::pose :init
            :position (ros::pos->tf-point (send coords :worldpos))
            :orientation (ros::rot->tf-quaternion (send coords :worldrot))))

(defun ros::coords->tf-pose-stamped (coords id)
  (let ((pose (ros::coords->tf-pose coords)))
    ;; PoseStamped = Header + Pose
    ;; Header = seq + frame_id
    (instance geometry_msgs::PoseStamped :init
              :header (instance roslib::header :init
                                :frame_id id
                                :stamp (ros::time-now))
              :pose pose)))

(defun ros::coords->tf-transform (coords)
  (instance geometry_msgs::transform :init
            :translation (ros::pos->tf-translation (send coords :worldpos))
            :rotation (ros::rot->tf-quaternion (send coords :worldrot))))

(defun ros::coords->tf-transform-stamped (coords id &optional (child_id ""))
    (let ((trans (ros::coords->tf-transform coords)))
      (instance geometry_msgs::TransformStamped :init
                :header (instance roslib::header :init :frame_id id :stamp (ros::time-now))
                :child_frame_id child_id :transform trans)))

;; tf->eus
(defun ros::tf-point->pos (point)
  (float-vector (* 1000.0 (send point :x)) (* 1000.0 (send point :y))  (* 1000.0 (send point :z))))

(defun ros::tf-quaternion->rot (quaternion)
  (quaternion2matrix
   (float-vector (send quaternion :w)
                 (send quaternion :x)
                 (send quaternion :y) 
                 (send quaternion :z))))

(defun ros::tf-pose->coords (pose)
  (make-coords :pos (ros::tf-point->pos (send pose :position))
               :rot (ros::tf-quaternion->rot (send pose :orientation))))

(defun ros::tf-pose-stamped->coords (pose-stamped)
  (make-cascoords :coords (ros::tf-pose->coords (send pose-stamped :pose))
                  :name (send pose-stamped :header :frame_id)))

(defun ros::tf-transform->coords (pose) (ros::tf-pose->coords pose))

;; helper functions
(defun ros::create-identity-quaternion () (ros::create-quaternion-from-rpy 0 0 0))
(defun ros::create-quaternion-from-rpy (roll pitch yaw)
  (let ((sin-roll  (sin (* roll  0.5))) (cos-roll  (cos (* roll  0.5)))
        (sin-pitch (sin (* pitch 0.5))) (cos-pitch (cos (* pitch 0.5)))
        (sin-yaw   (sin (* yaw   0.5))) (cos-yaw   (cos (* yaw   0.5))))
    (print (list sin-roll cos-roll
                 sin-pitch cos-pitch
                 sin-yaw cos-yaw))
    (float-vector (- (* sin-roll cos-pitch cos-yaw) (* cos-roll sin-pitch sin-yaw))
                  (+ (* cos-roll sin-pitch cos-yaw) (* sin-roll cos-pitch sin-yaw))
                  (- (* sin-roll cos-pitch sin-yaw) (* sin-roll sin-pitch cos-yaw))
                  (+ (* cos-roll cos-pitch cos-yaw) (* sin-roll sin-pitch sin-yaw)))))

(defun ros::create-quaternion-msg-from-rpy (roll pitch yaw)
  (let* ((q (ros::create-quaternion-from-rpy roll pitch yaw))
         (qx (elt q 1)) (qy (elt q 2)) (qz (elt q 3)) (qw (elt q 0)))
    (instance geometry_msgs::quaternion :init :x qx :y qy :z qz :w qw)))

;;
;; transfromer interface
;; http://www.ros.org/doc/api/tf/html/python/tf_python.html#transformer
;;
(defclass ros::transformer
  :super ros::object
  :slots (cobject))
(defmethod ros::transformer
  (:init
   (&optional (interpolating t) (cache-time 10.0))
   (setq cobject (ros::eustf-transformer interpolating cache-time))
   self)
  (:all-frames-as-string
   ()
   (ros::eustf-all-frames-as-string cobject))
  (:set-transform
   (trans &optional (auth ""))
   (ros::eustf-set-transform cobject))
  (:wait-for-transform
   (target-frame source-frame time timeout &optional (duration 0.01))
   (ros::eustf-wait-for-transform cobject
                                  target-frame source-frame
                                  (send time :sec-nsec) timeout duration))
  (:wait-for-transform-full
   (target-frame target-time source-frame source-time fixed-frame timeout &optional (duration 0.01))
   (ros::eustf-wait-for-transform-full cobject
                                       target-frame (send target-time :sec-nsec)
                                       source-frame (send source-time :sec-nsec)
                                       fixed-frame timeout duration))
  (:can-transform
   (target-frame source-frame time)
   (ros::eustf-can-transform cobject
                             target-frame source-frame (send time :sec-nsec)))
  (:can-transform-full
   (target-frame target-time source-frame source-time fixed-frame)
   (ros::eustf-can-transform-full cobject
                                  target-frame (send target-time :sec-nsec)
                                  source-frame (send source-time :sec-nsec)
                                  fixed-frame))
  (:chain
   (target-frame target-time source-frame source-time fixed-frame)
   (ros::eustf-chain cobject))
  (:clear () (ros::eustf-clear cobject))
  (:frame-exists (frame-id) (ros::eustf-all-frames-as-string cobject frame_id))
  (:get-frame-strings () (ros::eustf-get-frame-strings cobject))
  (:get-latest-common-time
   (source-frame target-frame)
   (let ((sec-nsec
          (ros::eustf-get-latest-common-time cobject source-frame target-frame)))
     (if sec-nsec
         (instance ros::time :init
                   :sec (car sec-nsec)
                   :nsec (cdr sec-nsec)))))
  (:lookup-transform
   (target-frame source-frame time)
   (let (ret)
     (setq ret (ros::eustf-lookup-transform cobject
                                            target-frame source-frame
                                            (send time :sec-nsec)))
     (make-cascoords :pos (float-vector
                           (* 1000.0 (elt ret 0))
                           (* 1000.0 (elt ret 1))
                           (* 1000.0 (elt ret 2)))
                     :rot
                     (quaternion2matrix
                      (float-vector (elt ret 3)
                                    (elt ret 4)
                                    (elt ret 5)
                                    (elt ret 6)))
                     :name target-frame)))
  (:lookup-transform-safe
   (target-frame source-frame time
    &optional (timeout 0.1) (duration 0.1))
      (if (send self :wait-for-transform target-frame source-frame time
                timeout duration)
          (send self :lookup-transform target-frame source-frame time)
        (progn
          (ros::ros-warn "cannot resolve transformation from ~A to ~A"
                         source-frame target-frame)          
          nil)))
  (:lookup-transform-full
   (target-frame target-time source-frame source-time fixed-frame)
   (let (ret)
     (setq ret (ros::eustf-lookup-transform-full cobject
                                                 target-frame (send target-time :sec-nsec)
                                                 source-frame (send source-time :sec-nsec)
                                                 fixed-frame))
     (make-cascoords :pos (float-vector
                           (* 1000.0 (elt ret 0))
                           (* 1000.0 (elt ret 1))
                           (* 1000.0 (elt ret 2)))
                     :rot
                     (quaternion2matrix
                      (float-vector (elt ret 3)
                                    (elt ret 4)
                                    (elt ret 5)
                                    (elt ret 6)))
                     :name target-frame)))
  (:lookup-velocity
   (reference-frame moving-frame time duration)
   (ros::eustf-lookup-velocity cobject reference-frame moving-frame time duration))
  (:get-parent
   (frame_id time)
   (ros::eustf-get-parent cobject frame_id (send time :sec-nsec)))
  ;;
  (:set-extrapolation-limit
   (distance)
   (ros::eustf-set-extrapolation-limit cobject distance))
  )

(defclass ros::transform-listener
  :super ros::transformer
  :slots ())
(defmethod ros::transform-listener
  (:init
   (&optional (cache-time 10.0) (spin-thread t))
   (setq cobject (ros::eustf-transform-listener cache-time spin-thread))
   self)
  (:transform-pose
   (target-frame pose-stamped)
   (let ((pose (float-vector (send pose-stamped :pose :position :x)
                             (send pose-stamped :pose :position :y)
                             (send pose-stamped :pose :position :z)
                             (send pose-stamped :pose :orientation :w)
                             (send pose-stamped :pose :orientation :x)
                             (send pose-stamped :pose :orientation :y)
                             (send pose-stamped :pose :orientation :z))))
     (let ((ret (ros::eustf-transform-pose cobject
					   target-frame
					   (send (send pose-stamped :header :stamp) :sec-nsec)
					   (send pose-stamped :header :frame_id)
					   pose)))
       (make-cascoords :pos (float-vector
			     (* 1000.0 (elt ret 0))
			     (* 1000.0 (elt ret 1))
			     (* 1000.0 (elt ret 2)))
		       :rot (quaternion2matrix (float-vector (elt ret 3)
                                                     (elt ret 4)
                                                     (elt ret 5)
                                                     (elt ret 6)))
		       :name target-frame))))
  (:transform-pose-safe
   (target-frame pose-stamped &optional (timeout 0.1) (duration 0.1))
   (if (send self :wait-for-transform target-frame
             (send pose-stamped :header :frame_id)
             (send pose-stamped :header :stamp)
             timeout duration)
       (send self :transform-pose target-frame pose-stamped)
     (progn
       (ros::ros-warn "cannot resolve transformation from ~A to ~A"
                      (send pose-stamped :header :frame_id)
                      target-frame)
       nil)))
  )

(defclass ros::transform-broadcaster
  :super ros::object
  :slots (cobject)
  )
(defmethod ros::transform-broadcaster
  (:init () (setq cobject (ros::eustf-transform-broadcaster)))
  (:send-transform
   (coords p-frame c-frame &optional time)
   (let ((pos (send coords :worldpos))
         (quat (matrix2quaternion (send coords :worldrot)))
         (tm (cond ((derivedp time ros::time) (send time :sec-nsec))
                   ((integer-vector-p time) time)
                   (t (send (ros::time-now) :sec-nsec))))
         )
     (ros::eustf-send-transform cobject pos quat p-frame c-frame tm)
     ))
  )